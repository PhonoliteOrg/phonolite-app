use std::cell::RefCell;
use std::fs::File;
use std::io::ErrorKind;
use std::path::Path;
use std::ptr;
use std::slice;
use std::str;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use symphonia::core::audio::{AudioBufferRef, SampleBuffer};
use symphonia::core::codecs::{Decoder, DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSource;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{Limit, MetadataOptions};
use symphonia::core::probe::Hint;
use symphonia::core::units::{Time, TimeBase};
use symphonia::default::{get_codecs, get_probe};

mod pinned_tls;
mod remote_source;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
    static LAST_ERROR_CODE: RefCell<i32> = const { RefCell::new(0) };
}

pub(crate) fn set_failure_code(code: i32) {
    LAST_ERROR_CODE.with(|slot| *slot.borrow_mut() = code);
}

pub(crate) fn failure_code() -> i32 {
    LAST_ERROR_CODE.with(|slot| *slot.borrow())
}

pub struct LocalAudioHandle {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn Decoder>,
    track_id: u32,
    sample_rate: u32,
    bit_depth: u32,
    source_channels: usize,
    output_channels: usize,
    duration_ms: i64,
    time_base: Option<TimeBase>,
    position_frames: u64,
    pending_skip_frames: u64,
    pending: Vec<i32>,
    pending_offset: usize,
    last_error: Option<String>,
    last_error_code: i32,
}

impl LocalAudioHandle {
    fn read(&mut self, out: &mut [i16]) -> Result<usize, String> {
        let mut precise = vec![0; out.len()];
        let count = self.read32(&mut precise)?;
        for (sample, precise) in out.iter_mut().zip(precise).take(count) {
            *sample = (precise >> 16) as i16;
        }

        Ok(count)
    }

    fn read32(&mut self, out: &mut [i32]) -> Result<usize, String> {
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
                    if decoded.spec().rate != self.sample_rate
                        || decoded.spec().channels.count() != self.source_channels
                    {
                        set_failure_code(-101);
                        return Err("audio format changed during playback".into());
                    }

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
) -> (Vec<i32>, u64, u64) {
    let spec = *decoded.spec();
    let mut sample_buffer = SampleBuffer::<i32>::new(decoded.capacity() as u64, spec);
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
    let mut hint = Hint::new();
    if let Some(extension) = path_ref.extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }

    open_source(Box::new(file), hint, start_ms)
}

fn open_remote_inner(
    url: &str,
    token: &str,
    server_pin: &str,
    start_ms: i64,
) -> Result<Box<LocalAudioHandle>, String> {
    let opening = Arc::new(AtomicBool::new(true));
    let source = remote_source::RemoteSource::open(url, token, server_pin, opening.clone())?;
    let result = open_source(Box::new(source), Hint::new(), start_ms);
    opening.store(false, Ordering::Release);

    result
}

fn open_source(
    source: Box<dyn MediaSource>,
    hint: Hint,
    start_ms: i64,
) -> Result<Box<LocalAudioHandle>, String> {
    let mss = MediaSourceStream::new(source, Default::default());

    let probed = get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions {
                limit_metadata_bytes: Limit::Maximum(64 * 1024),
                limit_visual_bytes: Limit::Maximum(0),
            },
        )
        .map_err(|err| {
            if failure_code() == 0 {
                set_failure_code(-101);
            }
            format!("probe failed: {err}")
        })?;
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
    if source_channels == 0 || source_channels > 2 {
        set_failure_code(-101);
        return Err("Original playback supports mono or stereo sources".to_string());
    }
    let output_channels = source_channels;
    let bit_depth = codec_params.bits_per_sample.unwrap_or(32);
    if bit_depth == 0 || bit_depth > 32 {
        set_failure_code(-101);
        return Err("Original playback supports source precision up to 32 bits".to_string());
    }
    let duration_ms = codec_params
        .n_frames
        .map(|frames| (frames.saturating_mul(1000) / sample_rate as u64) as i64)
        .unwrap_or(0);
    let time_base = codec_params.time_base;
    let decoder = get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|err| {
            set_failure_code(-101);
            format!("decoder create failed: {err}")
        })?;

    let mut handle = Box::new(LocalAudioHandle {
        format,
        decoder,
        track_id,
        sample_rate,
        bit_depth,
        source_channels,
        output_channels,
        duration_ms,
        time_base,
        position_frames: 0,
        pending_skip_frames: 0,
        pending: Vec::new(),
        pending_offset: 0,
        last_error: None,
        last_error_code: 0,
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

/// # Safety
/// `path` must address `path_len` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_open(
    path: *const u8,
    path_len: u64,
    start_ms: i64,
) -> *mut LocalAudioHandle {
    set_failure_code(0);
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

/// # Safety
/// Each input pointer must address its declared readable byte length for this
/// call. The returned handle is owned by the caller and must be closed once.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_open_remote(
    url: *const u8,
    url_len: u64,
    token: *const u8,
    token_len: u64,
    server_pin: *const u8,
    server_pin_len: u64,
    start_ms: i64,
) -> *mut LocalAudioHandle {
    set_failure_code(0);
    let input = |pointer: *const u8, length: u64| -> Result<&str, String> {
        if pointer.is_null() || length == 0 || length > 16_384 {
            set_failure_code(-100);
            return Err("invalid Original audio request".into());
        }

        str::from_utf8(slice::from_raw_parts(pointer, length as usize))
            .map_err(|_| "invalid Original audio request encoding".into())
    };
    let result = (|| {
        open_remote_inner(
            input(url, url_len)?,
            input(token, token_len)?,
            input(server_pin, server_pin_len)?,
            start_ms,
        )
    })();

    match result {
        Ok(handle) => Box::into_raw(handle),
        Err(error) => {
            set_last_error(error);
            ptr::null_mut()
        }
    }
}

/// # Safety
/// `handle` must be null or a live, exclusively borrowed decoder. `out` must
/// address `max_samples` writable i16 values without aliasing the decoder.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_read(
    handle: *mut LocalAudioHandle,
    out: *mut i16,
    max_samples: u64,
) -> i64 {
    set_failure_code(0);
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
            decoder.last_error_code = failure_code();
            -2
        }
    }
}

/// # Safety
/// `handle` must be null or a live, exclusively borrowed decoder. `out` must
/// address `max_samples` writable i32 values without aliasing the decoder.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_read32(
    handle: *mut LocalAudioHandle,
    out: *mut i32,
    max_samples: u64,
) -> i64 {
    set_failure_code(0);
    if out.is_null() || max_samples == 0 {
        return 0;
    }

    let decoder = match handle_mut(handle) {
        Ok(decoder) => decoder,
        Err(code) => return code,
    };
    let out = slice::from_raw_parts_mut(out, max_samples as usize);

    match decoder.read32(out) {
        Ok(read) => read as i64,
        Err(error) => {
            decoder.last_error = Some(error);
            decoder.last_error_code = failure_code();
            -2
        }
    }
}

/// # Safety
/// `handle` must be null or a live decoder exclusively borrowed for this call.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_seek(
    handle: *mut LocalAudioHandle,
    position_ms: i64,
) -> i64 {
    set_failure_code(0);
    let decoder = match handle_mut(handle) {
        Ok(decoder) => decoder,
        Err(code) => return code,
    };
    match decoder.seek(position_ms) {
        Ok(actual_ms) => actual_ms,
        Err(err) => {
            decoder.last_error = Some(err);
            decoder.last_error_code = failure_code();
            -2
        }
    }
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_sample_rate(handle: *mut LocalAudioHandle) -> i32 {
    handle
        .as_ref()
        .map(|handle| handle.sample_rate as i32)
        .unwrap_or(0)
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_bit_depth(handle: *mut LocalAudioHandle) -> i32 {
    handle
        .as_ref()
        .map(|handle| handle.bit_depth as i32)
        .unwrap_or(0)
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_channels(handle: *mut LocalAudioHandle) -> i32 {
    handle
        .as_ref()
        .map(|handle| handle.output_channels as i32)
        .unwrap_or(0)
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_duration_ms(handle: *mut LocalAudioHandle) -> i64 {
    handle
        .as_ref()
        .map(|handle| handle.duration_ms)
        .unwrap_or(0)
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_position_ms(handle: *mut LocalAudioHandle) -> i64 {
    handle
        .as_ref()
        .map(|handle| {
            (handle.position_frames.saturating_mul(1000) / handle.sample_rate as u64) as i64
        })
        .unwrap_or(0)
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_error_code(handle: *mut LocalAudioHandle) -> i32 {
    let code = handle
        .as_ref()
        .map(|handle| handle.last_error_code)
        .unwrap_or_else(failure_code);

    // The internal marker keeps a probe's network error distinct from an
    // unsupported file. Public transport failures retain the zero code.
    if code == -200 {
        0
    } else {
        code
    }
}

/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
/// `out` must address `out_len` writable bytes for this call.
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

/// # Safety
/// A non-null `handle` must be a live decoder returned by an open function,
/// uniquely owned by this call. It must never be used or closed again.
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
    fn original_mp3_keeps_decoder_precision_beyond_sixteen_bits() {
        let path = write_fixture("precise.mp3", include_bytes!("../tests/fixtures/tone.mp3"));
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        assert_eq!(decoder.bit_depth, 32);
        let mut samples = vec![0i32; decoder.output_channels * 4096];
        let count = decoder.read32(&mut samples).unwrap();
        assert!(samples[..count].iter().any(|sample| sample & 0xffff != 0));
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn decodes_flac_metadata_reads_seek_and_eof() {
        exercise_fixture("flac", include_bytes!("../tests/fixtures/tone.flac"));
    }

    #[test]
    fn original_flac_preserves_192khz_and_every_24bit_sample() {
        let values = [1, -1, 8_388_607, -8_388_608, 0x123456, -0x123456, 255, -255];
        exercise_precise_flac(24, &values);
    }

    #[test]
    fn original_flac_preserves_every_32bit_sample() {
        let values = [
            1,
            -1,
            i32::MAX,
            i32::MIN,
            0x12345678,
            -0x12345678,
            255,
            -255,
        ];
        exercise_precise_flac(32, &values);
    }

    #[test]
    fn seeks_within_a_large_32bit_flac_frame_after_eof() {
        let samples: Vec<i32> = (0..4096).map(|index| index * 31 + 1).collect();
        let path = write_fixture("large-seek-32.flac", &verbatim_flac(192_000, 32, &samples));
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        let mut output = vec![0; 8192];
        assert_eq!(decoder.read32(&mut output).unwrap(), 4096);
        assert_eq!(decoder.read32(&mut output).unwrap(), 0);

        assert_eq!(decoder.seek(5).unwrap(), 5);
        let read = decoder.read32(&mut output).unwrap();
        assert_eq!(&output[..read], &samples[960..]);
        assert_eq!(decoder.seek(0).unwrap(), 0);
        assert_eq!(decoder.read32(&mut output[..8]).unwrap(), 8);
        assert_eq!(&output[..8], &samples[..8]);
        drop(decoder);

        let mut decoder = open_inner(path.to_str().unwrap(), 5).unwrap();
        let read = decoder.read32(&mut output).unwrap();
        assert_eq!(&output[..read], &samples[960..]);
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    fn exercise_precise_flac(bits: u32, values: &[i32]) {
        let samples: Vec<i32> = values.iter().copied().cycle().take(16).collect();
        let bytes = verbatim_flac(192_000, bits, &samples);
        let path = write_fixture(&format!("precise-{bits}.flac"), &bytes);
        let mut decoder = open_inner(path.to_str().unwrap(), 0).expect("open high-resolution FLAC");
        assert_eq!(decoder.sample_rate, 192_000);
        assert_eq!(decoder.bit_depth, bits);
        let mut actual = vec![0; samples.len()];
        let count = decoder.read32(&mut actual).expect("read full precision");
        assert_eq!(count, samples.len());
        assert_eq!(
            actual,
            samples
                .iter()
                .map(|value| value << (32 - bits))
                .collect::<Vec<_>>()
        );
        assert_eq!(decoder.read32(&mut actual).unwrap(), 0);
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    fn verbatim_flac(rate: u32, bits: u32, samples: &[i32]) -> Vec<u8> {
        let mut file = b"fLaC\x80\0\0\x22".to_vec();
        file.extend_from_slice(&(samples.len() as u16).to_be_bytes());
        file.extend_from_slice(&(samples.len() as u16).to_be_bytes());
        file.extend_from_slice(&[0; 6]);
        let stream_info =
            ((rate as u64) << 44) | (((bits - 1) as u64) << 36) | samples.len() as u64;
        file.extend_from_slice(&stream_info.to_be_bytes());
        file.extend_from_slice(&[0; 16]);

        let mut frame = vec![
            0xff,
            0xf8,
            if samples.len() <= 256 { 0x60 } else { 0x70 },
            0,
            0,
        ];
        if samples.len() <= 256 {
            frame.push((samples.len() - 1) as u8);
        } else {
            frame.extend_from_slice(&((samples.len() - 1) as u16).to_be_bytes());
        }
        let crc = frame.iter().fold(0u8, |mut crc, byte| {
            crc ^= byte;
            for _ in 0..8 {
                crc = if crc & 0x80 != 0 {
                    (crc << 1) ^ 7
                } else {
                    crc << 1
                };
            }
            crc
        });
        frame.push(crc);
        frame.push(2);
        for sample in samples {
            frame.extend_from_slice(&sample.to_be_bytes()[4 - bits as usize / 8..]);
        }
        let crc = frame.iter().fold(0u16, |mut crc, byte| {
            crc ^= (*byte as u16) << 8;
            for _ in 0..8 {
                crc = if crc & 0x8000 != 0 {
                    (crc << 1) ^ 0x8005
                } else {
                    crc << 1
                };
            }
            crc
        });
        frame.extend_from_slice(&crc.to_be_bytes());
        file.extend_from_slice(&frame);

        file
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
