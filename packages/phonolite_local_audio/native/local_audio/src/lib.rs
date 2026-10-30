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
use symphonia::core::codecs::{
    CodecParameters, Decoder, DecoderOptions, CODEC_TYPE_AAC, CODEC_TYPE_ALAC, CODEC_TYPE_FLAC,
    CODEC_TYPE_MP3, CODEC_TYPE_NULL, CODEC_TYPE_OPUS, CODEC_TYPE_VORBIS,
};
use symphonia::core::errors::Error;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSource;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{Limit, MetadataOptions};
use symphonia::core::probe::Hint;
use symphonia::core::units::{Time, TimeBase};
use symphonia::default::get_probe;

mod opus;
mod pinned_tls;
mod quic_source;
mod remote_source;

#[cfg(test)]
mod quic_source_tests;
#[cfg(test)]
mod seek_tests;

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
    playable_frames: Option<u64>,
    time_base: Option<TimeBase>,
    position_frames: u64,
    pending_skip_frames: u64,
    pending: Vec<i32>,
    pending_offset: usize,
    seeked_to_end: bool,
    requires_accurate_seek: bool,
    strict_packets: bool,
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
        let _operation = quic_source::OperationGuard::enter();
        let max_samples = out.len() - (out.len() % self.output_channels);
        if max_samples == 0 {
            return Ok(0);
        }

        let mut written = 0;
        while written < max_samples {
            quic_source::check_operation()?;
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
        let _operation = quic_source::OperationGuard::enter();
        quic_source::check_operation()?;
        let requested_ms = position_ms.max(0) as u64;
        let target_frames = millis_to_frames(requested_ms, self.sample_rate);
        if let Some(total) = self.playable_frames {
            if target_frames >= total {
                self.decoder.reset();
                self.pending.clear();
                self.pending_offset = 0;
                self.position_frames = total;
                self.pending_skip_frames = 0;
                self.seeked_to_end = true;
                return Ok((u128::from(total) * 1000 / u128::from(self.sample_rate)) as i64);
            }
        }
        // Predictive codec state must converge before the
        // requested sample. Decode bounded pre-roll into the existing skip path.
        let seek_ms = if self.requires_accurate_seek {
            requested_ms.saturating_sub(1000)
        } else {
            requested_ms
        };
        let seconds = seek_ms / 1000;
        let frac = (seek_ms % 1000) as f64 / 1000.0;
        let time = Time::new(seconds, frac);
        let seeked = self
            .format
            .seek(
                if self.requires_accurate_seek {
                    SeekMode::Accurate
                } else {
                    SeekMode::Coarse
                },
                SeekTo::Time {
                    time,
                    track_id: Some(self.track_id),
                },
            )
            .map_err(|err| format!("seek failed: {err}"))?;
        quic_source::check_operation()?;
        self.decoder = opus::make_decoder(self.decoder.codec_params(), &DecoderOptions::default())
            .map_err(|error| format!("decoder reset failed: {error}"))?;
        self.seeked_to_end = false;
        self.pending.clear();
        self.pending_offset = 0;

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
        if self.seeked_to_end {
            return Ok(false);
        }
        loop {
            quic_source::check_operation()?;
            let packet = match self.format.next_packet() {
                Ok(packet) => packet,
                Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
                    return self.end_of_source();
                }
                Err(Error::ResetRequired) => {
                    if self.strict_packets {
                        set_failure_code(-101);
                        return Err("chained Opus streams are not supported".into());
                    }
                    self.decoder.reset();
                    continue;
                }
                Err(err) => return Err(format!("packet read failed: {err}")),
            };

            if packet.track_id() != self.track_id {
                continue;
            }

            let codec = self.decoder.codec_params().codec;
            match self.decoder.decode(&packet) {
                Ok(decoded) => {
                    if decoded.spec().rate != self.sample_rate
                        || decoded.spec().channels.count() != self.source_channels
                    {
                        set_failure_code(-101);
                        return Err("audio format changed during playback".into());
                    }

                    if codec == CODEC_TYPE_VORBIS && decoded.frames() == 0 {
                        // A post-seek overlap primer consumes packet time but
                        // emits no PCM. Do not clip that interval a second time.
                        let elapsed = self.time_base.map_or(0, |base| {
                            time_to_frames(base.calc_time(packet.dur()), self.sample_rate)
                        });
                        self.position_frames = self.position_frames.saturating_add(elapsed);
                        self.pending_skip_frames = self.pending_skip_frames.saturating_sub(elapsed);
                        continue;
                    }
                    let trim = packet_trim(codec, &packet, decoded.frames())?;
                    let (pending, skipped_frames, output_frames) = convert_decoded(
                        decoded,
                        self.source_channels,
                        self.output_channels,
                        self.pending_skip_frames,
                        trim,
                    );
                    self.pending_skip_frames =
                        self.pending_skip_frames.saturating_sub(skipped_frames);
                    self.position_frames = self
                        .position_frames
                        .saturating_add(skipped_frames)
                        .saturating_add(output_frames);
                    if self
                        .playable_frames
                        .is_some_and(|total| self.position_frames > total)
                    {
                        set_failure_code(-102);
                        return Err(
                            "audio source exceeds its advertised playable frame count".into()
                        );
                    }
                    self.pending = pending;
                    self.pending_offset = 0;
                    if self.pending.is_empty() {
                        continue;
                    }
                    return Ok(true);
                }
                Err(Error::DecodeError(error)) if self.strict_packets => {
                    set_failure_code(-102);
                    return Err(format!("invalid Opus packet: {error}"));
                }
                Err(Error::DecodeError(_)) => continue,
                Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
                    return self.end_of_source();
                }
                Err(Error::ResetRequired) => {
                    self.decoder.reset();
                    continue;
                }
                Err(err) => return Err(format!("decode failed: {err}")),
            }
        }
    }

    fn end_of_source(&self) -> Result<bool, String> {
        if self
            .playable_frames
            .is_some_and(|total| self.position_frames < total)
        {
            set_failure_code(-102);
            return Err(format!("audio source ended before its advertised playable frame count (decoded {}, expected {})", self.position_frames, self.playable_frames.unwrap()));
        }
        Ok(false)
    }
}

fn convert_decoded(
    decoded: AudioBufferRef<'_>,
    source_channels: usize,
    output_channels: usize,
    pending_skip_frames: u64,
    trim: (usize, usize),
) -> (Vec<i32>, u64, u64) {
    let spec = *decoded.spec();
    let mut sample_buffer = SampleBuffer::<i32>::new(decoded.capacity() as u64, spec);
    sample_buffer.copy_interleaved_ref(decoded);

    let all_samples = sample_buffer.samples();
    let samples =
        &all_samples[trim.0 * source_channels..all_samples.len() - trim.1 * source_channels];
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

fn packet_trim(
    codec: symphonia::core::codecs::CodecType,
    packet: &symphonia::core::formats::Packet,
    frames: usize,
) -> Result<(usize, usize), String> {
    // These decoders in Symphonia 0.5 do not apply demuxer packet trimming.
    // MP3, Vorbis and the bundled Opus decoder already apply it themselves.
    let trim = if matches!(codec, CODEC_TYPE_AAC | CODEC_TYPE_ALAC) {
        (packet.trim_start() as usize, packet.trim_end() as usize)
    } else {
        (0, 0)
    };
    if trim.0 + trim.1 > frames {
        set_failure_code(-102);
        return Err("source packet trim exceeds decoded audio".into());
    }
    Ok(trim)
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
            &FormatOptions {
                enable_gapless: true,
                ..FormatOptions::default()
            },
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
    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|track| {
            track.codec_params.codec == CODEC_TYPE_OPUS
                || (track.codec_params.codec != CODEC_TYPE_NULL
                    && symphonia::default::get_codecs()
                        .get_codec(track.codec_params.codec)
                        .is_some())
        })
        .ok_or_else(|| "no supported audio track found".to_string())?;
    let track_id = track.id;
    let codec_params = track.codec_params.clone();
    let mut decoder =
        opus::make_decoder(&codec_params, &DecoderOptions::default()).map_err(|err| {
            set_failure_code(-101);
            format!("decoder create failed: {err}")
        })?;
    let channels = codec_params.channels.or_else(|| {
        codec_params
            .channel_layout
            .map(|layout| layout.into_channels())
    });
    // MP4 AAC may carry its channel layout only in AudioSpecificConfig. Keep
    // the first decoded packet while discovering its actual PCM format.
    let initial = if channels.is_none() || codec_params.sample_rate.is_none() {
        Some(decode_initial_format(
            format.as_mut(),
            decoder.as_mut(),
            track_id,
        )?)
    } else {
        None
    };
    let sample_rate = initial
        .as_ref()
        .map(|(rate, _, _)| *rate)
        .or(codec_params.sample_rate)
        .filter(|rate| *rate > 0)
        .ok_or_else(|| "missing sample rate".to_string())?;
    let source_channels = initial
        .as_ref()
        .map(|(_, channels, _)| *channels)
        .or_else(|| channels.map(|channels| channels.count()))
        .ok_or_else(|| "missing channel layout".to_string())?;
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
    let playable_frames = exact_playable_frames(&codec_params, sample_rate);
    if codec_params.codec == CODEC_TYPE_OPUS && playable_frames.is_none() {
        set_failure_code(-102);
        return Err("Ogg Opus file has no complete final page".into());
    }
    let duration_ms = codec_params
        .n_frames
        .map(|frames| {
            let time_base = codec_params
                .time_base
                .unwrap_or(TimeBase::new(1, sample_rate));
            let milliseconds = u128::from(frames) * u128::from(time_base.numer) * 1000
                / u128::from(time_base.denom);
            milliseconds.min(i64::MAX as u128) as i64
        })
        .unwrap_or(0);
    let time_base = codec_params.time_base;
    let pending = initial.map(|(_, _, samples)| samples).unwrap_or_default();
    let position_frames = pending.len() as u64 / output_channels as u64;

    let mut handle = Box::new(LocalAudioHandle {
        format,
        decoder,
        track_id,
        sample_rate,
        bit_depth,
        source_channels,
        output_channels,
        duration_ms,
        playable_frames,
        time_base,
        position_frames,
        pending_skip_frames: 0,
        pending,
        pending_offset: 0,
        seeked_to_end: false,
        requires_accurate_seek: matches!(
            codec_params.codec,
            CODEC_TYPE_MP3 | CODEC_TYPE_OPUS | CODEC_TYPE_AAC | CODEC_TYPE_VORBIS
        ),
        strict_packets: codec_params.codec == CODEC_TYPE_OPUS,
        last_error: None,
        last_error_code: 0,
    });

    if start_ms > 0 {
        handle.seek(start_ms)?;
    }
    Ok(handle)
}

fn decode_initial_format(
    format: &mut dyn FormatReader,
    decoder: &mut dyn Decoder,
    track_id: u32,
) -> Result<(u32, usize, Vec<i32>), String> {
    loop {
        let packet = format.next_packet().map_err(|error| error.to_string())?;
        if packet.track_id() != track_id {
            continue;
        }
        let codec = decoder.codec_params().codec;
        let decoded = decoder.decode(&packet).map_err(|error| error.to_string())?;
        if decoded.frames() == 0 {
            continue;
        }
        let rate = decoded.spec().rate;
        let channels = decoded.spec().channels.count();
        if rate == 0 || !matches!(channels, 1 | 2) {
            set_failure_code(-101);
            return Err("unsupported source PCM format".into());
        }
        let trim = packet_trim(codec, &packet, decoded.frames())?;
        let (samples, _, _) = convert_decoded(decoded, channels, channels, 0, trim);
        if samples.is_empty() {
            continue;
        }
        return Ok((rate, channels, samples));
    }
}

fn millis_to_frames(ms: u64, sample_rate: u32) -> u64 {
    ms.saturating_mul(sample_rate as u64) / 1000
}

/// Keep unknown or estimated lengths unknown. In particular the MP3 demuxer
/// estimates VBR duration when no trusted Xing/LAME trimming data is present.
fn exact_playable_frames(parameters: &CodecParameters, sample_rate: u32) -> Option<u64> {
    if !matches!(
        parameters.codec,
        CODEC_TYPE_FLAC | CODEC_TYPE_MP3 | CODEC_TYPE_OPUS | CODEC_TYPE_AAC | CODEC_TYPE_ALAC
    ) {
        return None;
    }
    if parameters.codec == CODEC_TYPE_OPUS && parameters.delay.is_none() {
        return None;
    }
    if matches!(parameters.codec, CODEC_TYPE_AAC | CODEC_TYPE_ALAC)
        && (parameters.delay.is_none() || parameters.padding.is_none())
    {
        return None;
    }
    if parameters.codec == CODEC_TYPE_MP3
        && (parameters.delay.is_none() || parameters.padding.is_none())
    {
        return None;
    }
    let ticks = parameters.n_frames?;
    let time_base = parameters
        .time_base
        .unwrap_or(TimeBase::new(1, sample_rate));
    let numerator = u128::from(ticks) * u128::from(time_base.numer) * u128::from(sample_rate);
    let denominator = u128::from(time_base.denom);
    if numerator % denominator != 0 {
        return None;
    }
    u64::try_from(numerator / denominator).ok()
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
/// `source_handle` must be exclusively owned and all callback addresses must
/// remain valid until close. This function consumes the source even on failure.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_open_quic(
    source_handle: *mut std::ffi::c_void,
    read_range: Option<quic_source::ReadRange>,
    error_code: Option<quic_source::ErrorCode>,
    copy_error: Option<quic_source::CopyError>,
    close: Option<quic_source::Close>,
    start_ms: i64,
) -> *mut LocalAudioHandle {
    set_failure_code(0);
    let opening = Arc::new(AtomicBool::new(true));
    let result = (|| {
        let source = quic_source::QuicSource::open(
            source_handle,
            read_range,
            error_code,
            copy_error,
            close,
            opening.clone(),
        )?;
        open_source(Box::new(source), Hint::new(), start_ms)
    })();
    opening.store(false, Ordering::Release);
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

/// Exact playable PCM frames per channel, or -1 when unavailable.
/// Delay and padding have already been removed by the demuxer/decoder.
/// # Safety
/// `handle` must be null or a live decoder that is not concurrently mutated.
#[no_mangle]
pub unsafe extern "C" fn phonolite_local_audio_playable_frames(
    handle: *mut LocalAudioHandle,
) -> i64 {
    handle
        .as_ref()
        .and_then(|handle| handle.playable_frames)
        .and_then(|frames| i64::try_from(frames).ok())
        .unwrap_or(-1)
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
    use super::{
        exact_playable_frames, millis_to_frames, open_inner, time_to_frames, LocalAudioHandle,
    };
    use std::fs;
    use std::path::PathBuf;
    use std::process;
    use symphonia::core::units::Time;
    use symphonia::core::{
        codecs::{CodecParameters, CODEC_TYPE_MP3},
        units::TimeBase,
    };

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
    fn exact_length_rejects_estimated_mp3_and_fractional_timebases() {
        let mut parameters = CodecParameters::new();
        parameters.for_codec(CODEC_TYPE_MP3).with_n_frames(48_000);
        assert_eq!(exact_playable_frames(&parameters, 48_000), None);
        parameters.with_delay(576).with_padding(529);
        assert_eq!(exact_playable_frames(&parameters, 48_000), Some(48_000));
        parameters
            .with_time_base(TimeBase::new(1, 1000))
            .with_n_frames(1);
        assert_eq!(exact_playable_frames(&parameters, 44_100), None);
        parameters.with_n_frames(10);
        assert_eq!(exact_playable_frames(&parameters, 44_100), Some(441));
    }

    #[test]
    fn gapless_mp3_has_exact_length_and_seeks_in_the_trimmed_timeline() {
        let path = write_fixture("gapless.mp3", include_bytes!("../tests/fixtures/tone.mp3"));
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        let full = decode_all(&mut decoder);
        let total = decoder
            .playable_frames
            .expect("fixture has LAME/Xing trim metadata");
        assert_eq!(full.len() as u64, total * decoder.output_channels as u64);
        assert_eq!(decoder.duration_ms, 400);

        decoder.seek(0).unwrap();
        assert_eq!(decode_all(&mut decoder), full);
        decoder.seek(10).unwrap();
        let skip = millis_to_frames(10, decoder.sample_rate) as usize * decoder.output_channels;
        assert_eq!(decode_all(&mut decoder), full[skip..]);
        decoder.seek(200).unwrap();
        let suffix = decode_all(&mut decoder);
        let skip = millis_to_frames(200, decoder.sample_rate) as usize * decoder.output_channels;
        assert!(
            suffix == full[skip..],
            "seek must match the already-trimmed reference audio"
        );
        assert_eq!(decoder.seek(10_000).unwrap(), 400);
        assert!(decode_all(&mut decoder).is_empty());
        decoder.seek(0).unwrap();
        assert_eq!(decode_all(&mut decoder), full);
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn split_lossless_tracks_join_without_losing_sub_millisecond_tails() {
        let samples: Vec<i32> = (0..333).map(|index| index * 131 - 20_000).collect();
        let mut joined = Vec::new();
        for (name, part) in [
            ("gapless-a.flac", &samples[..137]),
            ("gapless-b.flac", &samples[137..]),
        ] {
            let path = write_fixture(name, &verbatim_flac(192_000, 32, part));
            let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
            assert_eq!(decoder.playable_frames, Some(part.len() as u64));
            joined.extend(decode_all(&mut decoder));
            drop(decoder);
            fs::remove_file(path).unwrap();
        }
        assert_eq!(joined, samples);
    }

    #[test]
    fn truncated_source_is_not_a_successful_track_end() {
        let samples: Vec<i32> = (0..100).collect();
        let mut bytes = verbatim_flac(192_000, 32, &samples);
        // Advertise one extra PCM frame without changing the encoded audio.
        let stream_info = ((192_000u64) << 44) | (31u64 << 36) | 101;
        bytes[18..26].copy_from_slice(&stream_info.to_be_bytes());
        let path = write_fixture("truncated-total.flac", &bytes);
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        let error = decoder.read32(&mut vec![0; 256]).unwrap_err();
        assert!(error.contains("advertised playable frame count"));
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn inconsistent_short_frame_total_is_rejected_without_truncating_music() {
        let samples: Vec<i32> = (0..100).collect();
        let mut bytes = verbatim_flac(192_000, 32, &samples);
        let stream_info = ((192_000u64) << 44) | (31u64 << 36) | 99;
        bytes[18..26].copy_from_slice(&stream_info.to_be_bytes());
        let path = write_fixture("short-total.flac", &bytes);
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        let error = decoder.read32(&mut vec![0; 256]).unwrap_err();
        assert!(error.contains("exceeds its advertised playable frame count"));
        drop(decoder);
        fs::remove_file(path).unwrap();
    }

    fn decode_all(decoder: &mut LocalAudioHandle) -> Vec<i32> {
        let mut output = Vec::new();
        let mut buffer = vec![0; decoder.output_channels * 137];
        loop {
            let count = decoder.read32(&mut buffer).unwrap();
            if count == 0 {
                return output;
            }
            output.extend_from_slice(&buffer[..count]);
        }
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

    pub(super) fn verbatim_flac(rate: u32, bits: u32, samples: &[i32]) -> Vec<u8> {
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
