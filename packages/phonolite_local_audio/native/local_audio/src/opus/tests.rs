use super::*;
use crate::{millis_to_frames, open_inner, LocalAudioHandle};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

#[repr(C)]
struct NativeEncoder {
    _private: [u8; 0],
}

extern "C" {
    fn opus_encoder_create(
        rate: c_int,
        channels: c_int,
        application: c_int,
        error: *mut c_int,
    ) -> *mut NativeEncoder;
    fn opus_encoder_destroy(encoder: *mut NativeEncoder);
    fn opus_encoder_ctl(encoder: *mut NativeEncoder, request: c_int, ...) -> c_int;
    fn opus_encode(
        encoder: *mut NativeEncoder,
        pcm: *const i16,
        frames: c_int,
        packet: *mut u8,
        capacity: c_int,
    ) -> c_int;
}

struct Encoder(*mut NativeEncoder);

impl Drop for Encoder {
    fn drop(&mut self) {
        unsafe { opus_encoder_destroy(self.0) };
    }
}

fn encoded_file(
    channels: usize,
    bitrate: u32,
    audible: usize,
    gain: i16,
    one_page: bool,
) -> Vec<u8> {
    let mut error = 0;
    let encoder =
        Encoder(unsafe { opus_encoder_create(48_000, channels as c_int, 2049, &mut error) });
    assert!(!encoder.0.is_null());
    assert_eq!(error, 0);
    assert_eq!(
        unsafe { opus_encoder_ctl(encoder.0, 4002, bitrate as c_int) },
        0
    );
    let mut delay = 0;
    assert_eq!(
        unsafe { opus_encoder_ctl(encoder.0, 4027, &mut delay as *mut c_int) },
        0
    );
    let mut header = b"OpusHead\x01".to_vec();
    header.push(channels as u8);
    header.extend_from_slice(&(delay as u16).to_le_bytes());
    header.extend_from_slice(&48_000u32.to_le_bytes());
    header.extend_from_slice(&gain.to_le_bytes());
    header.push(0);
    let tags = [
        b"OpusTags".as_slice(),
        &0u32.to_le_bytes(),
        &0u32.to_le_bytes(),
    ]
    .concat();
    let mut file = page(0, 2, 0, &[header]);
    file.extend(page(1, 0, 0, &[tags]));
    let packet_count = (audible + delay as usize).div_ceil(960);
    let mut packets = Vec::new();
    for index in 0..packet_count {
        let pcm: Vec<i16> = (0..960)
            .flat_map(|offset| {
                let frame = index * 960 + offset;
                let sample = if frame < audible {
                    ((frame as f64 * 0.0576).sin() * 6000.0) as i16
                } else {
                    0
                };
                (0..channels).map(move |channel| if channel == 0 { sample } else { -sample / 2 })
            })
            .collect();
        let mut packet = vec![0; 4000];
        let size = unsafe {
            opus_encode(
                encoder.0,
                pcm.as_ptr(),
                960,
                packet.as_mut_ptr(),
                packet.len() as c_int,
            )
        };
        assert!(size > 0);
        packet.truncate(size as usize);
        packets.push(packet);
    }
    if one_page {
        file.extend(page(2, 4, (audible + delay as usize) as u64, &packets));
    } else {
        for (index, packet) in packets.iter().enumerate() {
            let last = index + 1 == packet_count;
            let granule = if last {
                audible + delay as usize
            } else {
                (index + 1) * 960
            };
            file.extend(page(
                index as u32 + 2,
                if last { 4 } else { 0 },
                granule as u64,
                std::slice::from_ref(packet),
            ));
        }
    }
    file
}

fn page(sequence: u32, flags: u8, granule: u64, packets: &[Vec<u8>]) -> Vec<u8> {
    let mut segments = Vec::new();
    for packet in packets {
        segments.extend(std::iter::repeat_n(255, packet.len() / 255));
        segments.push((packet.len() % 255) as u8);
    }
    assert!(segments.len() < 256);
    let mut bytes = b"OggS\x00".to_vec();
    bytes.push(flags);
    bytes.extend_from_slice(&granule.to_le_bytes());
    bytes.extend_from_slice(&42u32.to_le_bytes());
    bytes.extend_from_slice(&sequence.to_le_bytes());
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes.push(segments.len() as u8);
    bytes.extend(segments);
    for packet in packets {
        bytes.extend(packet);
    }
    let mut crc = 0u32;
    for &byte in &bytes {
        crc ^= u32::from(byte) << 24;
        for _ in 0..8 {
            crc = if crc & 0x80000000 != 0 {
                (crc << 1) ^ 0x04c11db7
            } else {
                crc << 1
            };
        }
    }
    bytes[22..26].copy_from_slice(&crc.to_le_bytes());
    bytes
}

struct Fixture(PathBuf);

impl Fixture {
    fn new(bytes: &[u8]) -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "phonolite_opus_{}_{}.opus",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::write(&path, bytes).unwrap();
        Self(path)
    }

    fn open(&self, start: i64) -> Box<LocalAudioHandle> {
        open_inner(self.0.to_str().unwrap(), start).unwrap()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn decode_all(decoder: &mut LocalAudioHandle) -> Vec<i32> {
    let mut samples = Vec::new();
    let mut buffer = vec![0; 137 * decoder.output_channels];
    loop {
        let size = decoder.read32(&mut buffer).unwrap();
        if size == 0 {
            return samples;
        }
        samples.extend_from_slice(&buffer[..size]);
    }
}

#[test]
fn every_download_profile_decodes_mono_and_stereo_with_exact_trimming() {
    for bitrate in [64_000, 96_000, 128_000, 192_000] {
        for channels in [1, 2] {
            let fixture = Fixture::new(&encoded_file(channels, bitrate, 19_753, 0, true));
            let mut decoder = fixture.open(0);
            assert_eq!(decoder.sample_rate, 48_000);
            assert_eq!(decoder.output_channels, channels);
            assert_eq!(decoder.bit_depth, 32);
            assert_eq!(decoder.playable_frames, Some(19_753));
            let full = decode_all(&mut decoder);
            assert_eq!(full.len(), 19_753 * channels);
            assert!(full.iter().any(|sample| sample.abs() > 10_000_000));
            assert!(full.iter().any(|sample| sample & 0xffff != 0));
            decoder.seek(0).unwrap();
            assert_eq!(decode_all(&mut decoder), full);
            decoder.seek(200).unwrap();
            assert_eq!(decode_all(&mut decoder), full[9600 * channels..]);
        }
    }
}

#[test]
fn seeks_after_eof_and_at_start_offset_preserve_the_presentation_timeline() {
    let fixture = Fixture::new(&encoded_file(2, 96_000, 67_213, 0, false));
    let mut decoder = fixture.open(0);
    let full = decode_all(&mut decoder);
    assert_eq!(full.len(), 67_213 * 2);
    assert_eq!(decoder.seek(10_000).unwrap(), 1400);
    assert!(decode_all(&mut decoder).is_empty());
    for position in [10, 1200, 300, 0] {
        decoder.seek(position).unwrap();
        let actual = decode_all(&mut decoder);
        let skip = millis_to_frames(position as u64, 48_000) as usize * 2;
        let expected = &full[skip..];
        assert_eq!(actual.len(), expected.len());
        let error = actual
            .iter()
            .zip(expected)
            .map(|(&a, &b)| (f64::from(a) - f64::from(b)).powi(2))
            .sum::<f64>();
        let energy = expected
            .iter()
            .map(|&sample| f64::from(sample).powi(2))
            .sum::<f64>();
        assert!(
            error / energy < 0.0001,
            "seek mismatch at {position}: {}",
            error / energy
        );
    }
    assert_eq!(decode_all(&mut fixture.open(200)), full[19_200..]);
}

#[test]
fn opus_head_output_gain_is_applied() {
    let normal = Fixture::new(&encoded_file(1, 96_000, 19_200, 0, true));
    let quiet = Fixture::new(&encoded_file(1, 96_000, 19_200, -6 * 256, true));
    let energy = |fixture: &Fixture| {
        decode_all(&mut fixture.open(0))
            .iter()
            .map(|&sample| f64::from(sample).powi(2))
            .sum::<f64>()
    };
    let ratio = energy(&quiet) / energy(&normal);
    assert!((0.24..0.27).contains(&ratio));
    let mut decoder = quiet.open(0);
    let first = decode_all(&mut decoder);
    decoder.seek(0).unwrap();
    assert_eq!(decode_all(&mut decoder), first);
}

#[test]
fn sub_packet_audio_retains_every_audible_frame() {
    for length in [1, 137, 1001] {
        let fixture = Fixture::new(&encoded_file(1, 64_000, length, 0, true));
        let mut decoder = fixture.open(0);
        assert_eq!(decoder.playable_frames, Some(length as u64));
        assert_eq!(decode_all(&mut decoder).len(), length);
    }
}

#[test]
fn invalid_identification_and_packet_trimming_are_rejected() {
    let mut params = CodecParameters::new();
    params.for_codec(CODEC_TYPE_OPUS).with_extra_data(
        b"OpusHead\x01\x03\x00\x00\x80\xbb\x00\x00\x00\x00\x00"
            .to_vec()
            .into_boxed_slice(),
    );
    assert!(make_decoder(&params, &DecoderOptions::default()).is_err());
    params.extra_data.as_mut().unwrap()[9] = 1;
    let mut decoder = make_decoder(&params, &DecoderOptions::default()).unwrap();
    assert!(decoder
        .decode(&Packet::new_from_slice(0, 0, 0, &[]))
        .is_err());
    assert!(decoder
        .decode(&Packet::new_trimmed_from_slice(
            0,
            0,
            960,
            961,
            0,
            &[0xf8, 0xff, 0xfe]
        ))
        .is_err());
    assert_eq!(decoder.last_decoded().frames(), 0);
}

#[test]
fn truncated_or_corrupt_final_ogg_pages_are_rejected() {
    let complete = encoded_file(1, 96_000, 19_200, 0, false);
    let mut truncated = complete.clone();
    truncated.truncate(truncated.len() - 8);
    let fixture = Fixture::new(&truncated);
    assert!(open_inner(fixture.0.to_str().unwrap(), 0).is_err());
    let mut corrupt = complete;
    *corrupt.last_mut().unwrap() ^= 0x80;
    let fixture = Fixture::new(&corrupt);
    assert!(open_inner(fixture.0.to_str().unwrap(), 0).is_err());
}

#[test]
#[ignore = "requires the server's independently generated rendition fixtures"]
fn server_generated_downloads_play_and_seek_in_the_app_decoder() {
    let directory = PathBuf::from(
        std::env::var_os("PHONOLITE_DOWNLOAD_FIXTURES").expect("set PHONOLITE_DOWNLOAD_FIXTURES"),
    );
    for bitrate in [64_000, 96_000, 128_000, 192_000] {
        let path = directory.join(format!("tone_{bitrate}.opus"));
        let mut decoder = open_inner(path.to_str().unwrap(), 0).unwrap();
        assert_eq!(decoder.sample_rate, 48_000);
        assert_eq!(decoder.output_channels, 2);
        assert_eq!(decoder.playable_frames, Some(19_200));
        let full = decode_all(&mut decoder);
        assert_eq!(full.len(), 38_400);
        assert!(full.iter().any(|sample| sample.abs() > 1_000_000));
        decoder.seek(100).unwrap();
        assert_eq!(decode_all(&mut decoder), full[9600..]);
    }
}
