use std::cell::RefCell;
use std::fs::File;
use std::io::ErrorKind;
use std::path::Path;
use std::ptr;
use std::slice;
use std::str;

use symphonia::core::audio::{AudioBufferRef, SampleBuffer};
use symphonia::core::codecs::{Decoder, DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::{Time, TimeBase};
use symphonia::default::{get_codecs, get_probe};

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

pub struct LocalAudioHandle {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn Decoder>,
    track_id: u32,
    sample_rate: u32,
    source_channels: usize,
    output_channels: usize,
    duration_ms: i64,
    time_base: Option<TimeBase>,
    position_frames: u64,
    pending_skip_frames: u64,
    pending: Vec<i16>,
    pending_offset: usize,
    last_error: Option<String>,
}

impl LocalAudioHandle {
    fn read(&mut self, out: &mut [i16]) -> Result<usize, String> {
        let max_samples = out.len() - (out.len() % self.output_channels);
        if max_samples == 0 {
            return Ok(0);
        }

        let mut written = 0;
        while written < max_samples {
            if self.pending_offset < self.pending.len() {
                let available = self.pending.len() - self.pending_offset;
                let wanted = max_samples - written;
                let to_copy = available.min(wanted);
                out[written..written + to_copy].copy_from_slice(
                    &self.pending[self.pending_offset..self.pending_offset + to_copy],
                );
                self.pending_offset += to_copy;
                written += to_copy;
                if self.pending_offset >= self.pending.len() {
                    self.pending.clear();
                    self.pending_offset = 0;
                }
                continue;
            }

            if !self.decode_next_packet()? {
                break;
            }
        }

        Ok(written)
    }

    fn seek(&mut self, position_ms: i64) -> Result<i64, String> {
        let requested_ms = position_ms.max(0) as u64;
        let seconds = requested_ms / 1000;
        let frac = (requested_ms % 1000) as f64 / 1000.0;
        let time = Time::new(seconds, frac);
        let seeked = self
            .format
            .seek(
                SeekMode::Coarse,
                SeekTo::Time {
                    time,
                    track_id: Some(self.track_id),
                },
            )
            .map_err(|err| format!("seek failed: {err}"))?;
        self.decoder.reset();
        self.pending.clear();
        self.pending_offset = 0;

        let target_frames = millis_to_frames(requested_ms, self.sample_rate);
        let actual_frames = self
            .time_base
            .map(|time_base| {
                time_to_frames(time_base.calc_time(seeked.actual_ts), self.sample_rate)
            })
            .unwrap_or(0);
        self.position_frames = actual_frames.min(target_frames);
        self.pending_skip_frames = target_frames.saturating_sub(self.position_frames);
        Ok(requested_ms as i64)
    }

    fn decode_next_packet(&mut self) -> Result<bool, String> {
        loop {
            let packet = match self.format.next_packet() {
                Ok(packet) => packet,
                Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
                    return Ok(false);
                }
                Err(Error::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(err) => return Err(format!("packet read failed: {err}")),
            };

            if packet.track_id() != self.track_id {
                continue;
            }

            match self.decoder.decode(&packet) {
                Ok(decoded) => {
                    let (pending, skipped_frames, output_frames) = convert_decoded(
                        decoded,
                        self.source_channels,
                        self.output_channels,
                        self.pending_skip_frames,
                    );
                    self.pending_skip_frames =
                        self.pending_skip_frames.saturating_sub(skipped_frames);
                    self.position_frames = self
                        .position_frames
                        .saturating_add(skipped_frames)
                        .saturating_add(output_frames);
                    self.pending = pending;
                    self.pending_offset = 0;
                    if self.pending.is_empty() {
                        continue;
                    }
                    return Ok(true);
                }
                Err(Error::DecodeError(_)) => continue,
                Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
                    return Ok(false);
                }
                Err(Error::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(err) => return Err(format!("decode failed: {err}")),
            }
        }
    }
}

fn convert_decoded(
    decoded: AudioBufferRef<'_>,
    source_channels: usize,
    output_channels: usize,
    pending_skip_frames: u64,
) -> (Vec<i16>, u64, u64) {
    let spec = *decoded.spec();
    let mut sample_buffer = SampleBuffer::<i16>::new(decoded.capacity() as u64, spec);
    sample_buffer.copy_interleaved_ref(decoded);

    let samples = sample_buffer.samples();
    if source_channels == 0 || samples.is_empty() {
        return (Vec::new(), 0, 0);
    }

    let frames = samples.len() / source_channels;
    if frames == 0 {
        return (Vec::new(), 0, 0);
    }

    let skip_frames = pending_skip_frames.min(frames as u64) as usize;
    if skip_frames >= frames {
        return (Vec::new(), skip_frames as u64, 0);
    }

    let output_frames = frames - skip_frames;
    let mut out = Vec::with_capacity(output_frames * output_channels);
    if source_channels == output_channels {
        let start = skip_frames * source_channels;
        let end = frames * source_channels;
        out.extend_from_slice(&samples[start..end]);
    } else if output_channels == 1 {
        for frame in skip_frames..frames {
            out.push(samples[frame * source_channels]);
        }
    } else {
        for frame in skip_frames..frames {
            let base = frame * source_channels;
            out.push(samples[base]);
            out.push(samples[base + 1]);
        }
    }
    (out, skip_frames as u64, output_frames as u64)
}

fn open_inner(path: &str, start_ms: i64) -> Result<Box<LocalAudioHandle>, String> {
    let path_ref = Path::new(path);
    let file = File::open(path_ref).map_err(|err| format!("open failed: {err}"))?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(extension) = path_ref.extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    let probed = get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|err| format!("probe failed: {err}"))?;
    let format = probed.format;
    let track = format
        .default_track()
        .or_else(|| {
            format
                .tracks()
                .iter()
                .find(|track| track.codec_params.codec != CODEC_TYPE_NULL)
        })
        .ok_or_else(|| "no supported audio track found".to_string())?;
    let track_id = track.id;
    let codec_params = track.codec_params.clone();
    let sample_rate = codec_params
        .sample_rate
        .ok_or_else(|| "missing sample rate".to_string())?;
    let source_channels = codec_params
        .channels
        .ok_or_else(|| "missing channel layout".to_string())?
        .count();
    if source_channels == 0 {
        return Err("invalid channel count".to_string());
    }
    let output_channels = if source_channels == 1 { 1 } else { 2 };
    let duration_ms = codec_params
        .n_frames
        .map(|frames| (frames.saturating_mul(1000) / sample_rate as u64) as i64)
        .unwrap_or(0);
    let time_base = codec_params.time_base;
    let decoder = get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|err| format!("decoder create failed: {err}"))?;

    let mut handle = Box::new(LocalAudioHandle {
        format,
        decoder,
        track_id,
        sample_rate,
        source_channels,
        output_channels,
        duration_ms,
        time_base,
        position_frames: 0,
        pending_skip_frames: 0,
        pending: Vec::new(),
        pending_offset: 0,
        last_error: None,
    });

    if start_ms > 0 {
        handle.seek(start_ms)?;
    }
    Ok(handle)
}

fn millis_to_frames(ms: u64, sample_rate: u32) -> u64 {
    ms.saturating_mul(sample_rate as u64) / 1000
}

fn time_to_frames(time: Time, sample_rate: u32) -> u64 {
    ((time.seconds as f64 + time.frac) * sample_rate as f64).round() as u64
}

fn set_last_error(message: String) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = Some(message);
    });
}

unsafe fn handle_mut<'a>(handle: *mut LocalAudioHandle) -> Result<&'a mut LocalAudioHandle, i64> {
    handle.as_mut().ok_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_open(
    path: *const u8,
    path_len: u64,
    start_ms: i64,
) -> *mut LocalAudioHandle {
    if path.is_null() || path_len == 0 {
        set_last_error("invalid path".to_string());
        return ptr::null_mut();
    }
    let bytes = slice::from_raw_parts(path, path_len as usize);
    let path = match str::from_utf8(bytes) {
        Ok(path) => path,
        Err(err) => {
            set_last_error(format!("path is not valid UTF-8: {err}"));
            return ptr::null_mut();
        }
    };
    match open_inner(path, start_ms) {
        Ok(handle) => Box::into_raw(handle),
        Err(err) => {
            set_last_error(err);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_read(
    handle: *mut LocalAudioHandle,
    out: *mut i16,
    max_samples: u64,
) -> i64 {
    if out.is_null() || max_samples == 0 {
        return 0;
    }
    let decoder = match handle_mut(handle) {
        Ok(decoder) => decoder,
        Err(code) => return code,
    };
    let out = slice::from_raw_parts_mut(out, max_samples as usize);
    match decoder.read(out) {
        Ok(read) => read as i64,
        Err(err) => {
            decoder.last_error = Some(err);
            -2
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_seek(
    handle: *mut LocalAudioHandle,
    position_ms: i64,
) -> i64 {
    let decoder = match handle_mut(handle) {
        Ok(decoder) => decoder,
        Err(code) => return code,
    };
    match decoder.seek(position_ms) {
        Ok(actual_ms) => actual_ms,
        Err(err) => {
            decoder.last_error = Some(err);
            -2
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_sample_rate(handle: *mut LocalAudioHandle) -> i32 {
    handle
        .as_ref()
        .map(|handle| handle.sample_rate as i32)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_channels(handle: *mut LocalAudioHandle) -> i32 {
    handle
        .as_ref()
        .map(|handle| handle.output_channels as i32)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_duration_ms(handle: *mut LocalAudioHandle) -> i64 {
    handle
        .as_ref()
        .map(|handle| handle.duration_ms)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_position_ms(handle: *mut LocalAudioHandle) -> i64 {
    handle
        .as_ref()
        .map(|handle| {
            (handle.position_frames.saturating_mul(1000) / handle.sample_rate as u64) as i64
        })
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_last_error(
    handle: *mut LocalAudioHandle,
    out: *mut u8,
    out_len: u64,
) -> u64 {
    if out.is_null() || out_len == 0 {
        return 0;
    }
    let message = if let Some(handle) = handle.as_ref() {
        handle.last_error.clone()
    } else {
        LAST_ERROR.with(|slot| slot.borrow().clone())
    };
    let Some(message) = message else {
        return 0;
    };
    let bytes = message.as_bytes();
    let writable = (out_len as usize).saturating_sub(1);
    let copied = bytes.len().min(writable);
    if copied > 0 {
        ptr::copy_nonoverlapping(bytes.as_ptr(), out, copied);
    }
    *out.add(copied) = 0;
    copied as u64
}

#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_close(handle: *mut LocalAudioHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[cfg(test)]
mod tests {
    use super::{millis_to_frames, open_inner, time_to_frames};
    use std::fs;
    use std::path::PathBuf;
    use std::process;
    use symphonia::core::units::Time;

    #[test]
    fn converts_milliseconds_to_frames() {
        assert_eq!(millis_to_frames(1_000, 48_000), 48_000);
        assert_eq!(millis_to_frames(250, 44_100), 11_025);
    }

    #[test]
    fn converts_time_to_frames() {
        assert_eq!(time_to_frames(Time::new(2, 0.5), 48_000), 120_000);
    }

    #[test]
    fn decodes_mp3_metadata_reads_seek_and_eof() {
        exercise_fixture("mp3", include_bytes!("../tests/fixtures/tone.mp3"));
    }

    #[test]
    fn decodes_flac_metadata_reads_seek_and_eof() {
        exercise_fixture("flac", include_bytes!("../tests/fixtures/tone.flac"));
    }

    #[test]
    fn rejects_corrupt_or_unsupported_files() {
        let path = write_fixture("corrupt.mp3", b"this is not audio");
        let result = open_inner(path.to_str().unwrap(), 0);
        let _ = fs::remove_file(path);
        assert!(result.is_err());
    }

    fn exercise_fixture(extension: &str, bytes: &[u8]) {
        let path = write_fixture(&format!("tone.{extension}"), bytes);
        let path_str = path.to_str().unwrap();
        let mut decoder = open_inner(path_str, 0).expect("open fixture");

        assert!(decoder.sample_rate > 0);
        assert!(decoder.output_channels == 1 || decoder.output_channels == 2);
        assert!(decoder.duration_ms >= 0);

        let mut pcm = vec![0i16; decoder.output_channels * 4096];
        let first = decoder.read(&mut pcm).expect("initial read");
        assert!(first > 0);
        assert_eq!(first % decoder.output_channels, 0);
        assert!(pcm[..first].iter().any(|sample| *sample != 0));

        let near_start = decoder.seek(10).expect("seek near start");
        assert!(near_start >= 0);
        let after_start = decoder.read(&mut pcm).expect("read after start seek");
        assert!(after_start > 0);

        if decoder.duration_ms > 180 {
            let middle = decoder.duration_ms / 2;
            let after_middle_seek = decoder.seek(middle).expect("seek middle");
            assert!(after_middle_seek >= middle.saturating_sub(1));
            let after_middle = decoder.read(&mut pcm).expect("read after middle seek");
            assert!(after_middle > 0);

            let near_end = (decoder.duration_ms - 80).max(0);
            let after_end_seek = decoder.seek(near_end).expect("seek near end");
            assert!(after_end_seek >= near_end.saturating_sub(1));
        }

        let mut saw_eof = false;
        for _ in 0..256 {
            let read = decoder.read(&mut pcm).expect("read until eof");
            if read == 0 {
                saw_eof = true;
                break;
            }
        }
        let _ = fs::remove_file(path);
        assert!(saw_eof);
    }

    fn write_fixture(name: &str, bytes: &[u8]) -> PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!("phonolite_local_audio_{}_{}", process::id(), name));
        fs::write(&path, bytes).expect("write fixture");
        path
    }
}
