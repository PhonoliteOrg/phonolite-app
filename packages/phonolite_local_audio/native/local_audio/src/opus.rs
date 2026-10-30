//! Ogg Opus packets decoded by the app's bundled libopus, preserving float output.

use std::ffi::c_int;
use std::ptr::NonNull;

use symphonia::core::audio::{
    AsAudioBufferRef, AudioBuffer, AudioBufferRef, Channels, Signal, SignalSpec,
};
use symphonia::core::codecs::{
    CodecDescriptor, CodecParameters, Decoder, DecoderOptions, FinalizeResult, CODEC_TYPE_OPUS,
};
use symphonia::core::errors::{decode_error, unsupported_error, Error, Result};
use symphonia::core::formats::Packet;

const OPUS_RESET_STATE: c_int = 4028;
const OPUS_SET_GAIN_REQUEST: c_int = 4034;
const MAX_FRAMES: usize = 5760;

#[repr(C)]
struct NativeDecoder {
    _private: [u8; 0],
}

extern "C" {
    fn opus_decoder_create(rate: c_int, channels: c_int, error: *mut c_int) -> *mut NativeDecoder;
    fn opus_decoder_destroy(decoder: *mut NativeDecoder);
    fn opus_decoder_ctl(decoder: *mut NativeDecoder, request: c_int, ...) -> c_int;
    fn opus_decode_float(
        decoder: *mut NativeDecoder,
        data: *const u8,
        length: c_int,
        pcm: *mut f32,
        frames: c_int,
        fec: c_int,
    ) -> c_int;
}

pub(super) fn make_decoder(
    params: &CodecParameters,
    options: &DecoderOptions,
) -> Result<Box<dyn Decoder>> {
    if params.codec == CODEC_TYPE_OPUS {
        Ok(Box::new(OpusDecoder::try_new(params, options)?))
    } else {
        symphonia::default::get_codecs().make(params, options)
    }
}

struct OpusDecoder {
    params: CodecParameters,
    native: NonNull<NativeDecoder>,
    channels: usize,
    interleaved: Vec<f32>,
    buffer: AudioBuffer<f32>,
    reset_failed: bool,
}

// The handle owns its decoder, and every libopus state mutation requires &mut self.
unsafe impl Send for OpusDecoder {}
unsafe impl Sync for OpusDecoder {}

impl Drop for OpusDecoder {
    fn drop(&mut self) {
        unsafe { opus_decoder_destroy(self.native.as_ptr()) };
    }
}

impl Decoder for OpusDecoder {
    fn try_new(params: &CodecParameters, _options: &DecoderOptions) -> Result<Self> {
        let header = params
            .extra_data
            .as_deref()
            .ok_or(Error::DecodeError("Opus identification header is missing"))?;
        if params.codec != CODEC_TYPE_OPUS
            || header.len() < 19
            || &header[..8] != b"OpusHead"
            || header[8] > 15
        {
            return decode_error("invalid Opus identification header");
        }
        let channels = usize::from(header[9]);
        if !matches!(channels, 1 | 2) {
            return unsupported_error("Opus playback supports mono and stereo audio");
        }
        match header[18] {
            0 => {}
            1 if header.len() >= 21 + channels
                && header[19] == 1
                && usize::from(header[20]) == channels - 1
                && header[21..21 + channels]
                    .iter()
                    .copied()
                    .eq(0..channels as u8) => {}
            _ => return unsupported_error("unsupported Opus channel mapping"),
        }
        let mask = if channels == 1 {
            Channels::FRONT_LEFT
        } else {
            Channels::FRONT_LEFT | Channels::FRONT_RIGHT
        };
        if params.sample_rate.is_some_and(|rate| rate != 48_000)
            || params.channels.is_some_and(|layout| layout != mask)
        {
            return decode_error("Opus codec parameters disagree with the identification header");
        }
        let mut error = 0;
        let raw = unsafe { opus_decoder_create(48_000, channels as c_int, &mut error) };
        let native =
            NonNull::new(raw).ok_or(Error::Unsupported("libopus initialization failed"))?;
        if error != 0 {
            unsafe { opus_decoder_destroy(native.as_ptr()) };
            return unsupported_error("libopus initialization failed");
        }
        let gain = i16::from_le_bytes([header[16], header[17]]);
        let result =
            unsafe { opus_decoder_ctl(native.as_ptr(), OPUS_SET_GAIN_REQUEST, c_int::from(gain)) };
        if result != 0 {
            unsafe { opus_decoder_destroy(native.as_ptr()) };
            return decode_error("invalid Opus output gain");
        }
        Ok(Self {
            params: params.clone(),
            native,
            channels,
            interleaved: vec![0.0; MAX_FRAMES * channels],
            buffer: AudioBuffer::new(MAX_FRAMES as u64, SignalSpec::new(48_000, mask)),
            reset_failed: false,
        })
    }

    fn supported_codecs() -> &'static [CodecDescriptor] {
        &[CodecDescriptor {
            codec: CODEC_TYPE_OPUS,
            short_name: "opus",
            long_name: "Opus (bundled libopus)",
            inst_func: make_decoder,
        }]
    }

    fn reset(&mut self) {
        self.buffer.clear();
        self.reset_failed =
            unsafe { opus_decoder_ctl(self.native.as_ptr(), OPUS_RESET_STATE) } != 0;
    }

    fn codec_params(&self) -> &CodecParameters {
        &self.params
    }

    fn decode(&mut self, packet: &Packet) -> Result<AudioBufferRef<'_>> {
        self.buffer.clear();
        if self.reset_failed || packet.data.is_empty() || packet.data.len() > c_int::MAX as usize {
            return decode_error("invalid Opus packet or decoder state");
        }
        let decoded = unsafe {
            opus_decode_float(
                self.native.as_ptr(),
                packet.data.as_ptr(),
                packet.data.len() as c_int,
                self.interleaved.as_mut_ptr(),
                MAX_FRAMES as c_int,
                0,
            )
        };
        if decoded < 0 {
            return decode_error("invalid Opus packet");
        }
        let frames = decoded as usize;
        let start = packet.trim_start() as usize;
        let end = packet.trim_end() as usize;
        if start.saturating_add(end) > frames {
            return decode_error("Opus packet trimming exceeds decoded frames");
        }
        self.buffer.render_reserved(Some(frames - start - end));
        for channel in 0..self.channels {
            for (output, frame) in self.buffer.chan_mut(channel).iter_mut().zip(
                self.interleaved[start * self.channels..(frames - end) * self.channels]
                    .chunks_exact(self.channels),
            ) {
                *output = frame[channel];
            }
        }
        Ok(self.buffer.as_audio_buffer_ref())
    }

    fn finalize(&mut self) -> FinalizeResult {
        FinalizeResult::default()
    }

    fn last_decoded(&self) -> AudioBufferRef<'_> {
        self.buffer.as_audio_buffer_ref()
    }
}

#[cfg(test)]
mod tests;
