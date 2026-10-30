use std::io::Cursor;

use symphonia::core::probe::Hint;

use crate::{open_source, LocalAudioHandle};

#[path = "../tests/presentation_fixtures.rs"]
pub(crate) mod fixtures;

fn open(bytes: &[u8], start_ms: i64) -> Box<LocalAudioHandle> {
    open_source(Box::new(Cursor::new(bytes.to_vec())), Hint::new(), start_ms).unwrap()
}

fn decode(decoder: &mut LocalAudioHandle) -> Vec<i32> {
    let mut samples = Vec::new();
    let mut output = [0; 4096];
    loop {
        let count = decoder.read32(&mut output).unwrap();
        if count == 0 {
            return samples;
        }
        samples.extend_from_slice(&output[..count]);
    }
}

#[test]
fn multi_frame_flac_repeated_seeks_after_read_ahead_eof_preserve_every_sample() {
    let bytes = include_bytes!("../tests/fixtures/tone.flac");
    let mut decoder = open(bytes, 0);
    let full = decode(&mut decoder);
    assert_eq!(full.len(), 17_640 * 2);
    for position in [10, 200, 0, 350, 10] {
        assert_eq!(decoder.seek(position).unwrap(), position);
        let offset = position as usize * 44_100 / 1000 * decoder.output_channels;
        assert_eq!(
            decode(&mut decoder),
            full[offset..],
            "seek {position}ms after EOF"
        );
    }
}

#[test]
fn lossy_source_seeks_match_uninterrupted_pcm_and_preserve_the_full_suffix() {
    for (name, bytes) in [
        (
            "vorbis.ogg",
            include_bytes!("../tests/fixtures/vorbis.ogg").as_slice(),
        ),
        (
            "aac.m4a",
            include_bytes!("../tests/fixtures/aac.m4a").as_slice(),
        ),
        (
            "tone.aac",
            include_bytes!("../tests/fixtures/tone.aac").as_slice(),
        ),
    ] {
        let mut decoder = open(bytes, 0);
        let full = decode(&mut decoder);
        if name == "vorbis.ogg" {
            assert_eq!(full.len(), 19_200 * 2, "Vorbis tail padding is not music");
        }
        for position in [10, 200, 0, 350] {
            assert_eq!(decoder.seek(position).unwrap(), position);
            let offset =
                position as usize * decoder.sample_rate as usize / 1000 * decoder.output_channels;
            let actual = decode(&mut decoder);
            assert_eq!(
                actual.len(),
                full.len() - offset,
                "{name}: seek {position}ms"
            );
            assert_eq!(actual, full[offset..], "{name}: seek {position}ms");
            assert_eq!(
                decode(&mut open(bytes, position)),
                full[offset..],
                "{name}: fresh {position}ms"
            );
        }
    }
}

#[test]
fn multi_page_vorbis_seeks_beyond_preroll_keep_the_exact_presentation_suffix() {
    let bytes = fixtures::long_vorbis(include_bytes!("../tests/fixtures/vorbis.ogg"));
    let mut decoder = open(&bytes, 0);
    let full = decode(&mut decoder);
    assert_eq!(full.len(), 436_992 * 2);
    for position in [3100, 8000, 2100, 1000, 0, 9050] {
        assert_eq!(decoder.seek(position).unwrap(), position);
        let offset = position as usize * 48 * 2;
        assert_eq!(
            decode(&mut decoder),
            full[offset..],
            "post-EOF {position}ms"
        );
        assert_eq!(
            decode(&mut open(&bytes, position)),
            full[offset..],
            "fresh {position}ms"
        );
    }
}

#[test]
fn aac_edit_list_removes_declared_priming_and_padding_in_reads_and_seeks() {
    let reference = decode(&mut open(include_bytes!("../tests/fixtures/tone.aac"), 0));
    // The M4A's elst maps 400 movie ticks (1000 Hz) from media frame 1024
    // at 48 kHz. The independently packaged ADTS exposes the raw access units.
    let presentation = &reference[1024 * 2..(1024 + 19_200) * 2];
    let bytes = include_bytes!("../tests/fixtures/aac.m4a");
    let mut decoder = open(bytes, 0);
    assert_eq!(decoder.duration_ms, 400);
    assert_eq!(decoder.playable_frames, Some(19_200));
    assert_eq!(decode(&mut decoder), presentation);
    for position in [0, 200, 10, 350, 399] {
        decoder.seek(position).unwrap();
        let expected = &presentation[position as usize * 48 * 2..];
        assert_eq!(decode(&mut decoder), expected, "post-EOF {position}ms");
        assert_eq!(
            decode(&mut open(bytes, position)),
            expected,
            "fresh {position}ms"
        );
    }
    assert_eq!(decoder.seek(400).unwrap(), 400);
    assert!(decode(&mut decoder).is_empty());
}

#[test]
fn long_aac_presentation_seeks_keep_the_exact_frame_interval_after_eof() {
    let adts = include_bytes!("../tests/fixtures/tone.aac").repeat(30);
    let raw = decode(&mut open(&adts, 0));
    let (bytes, frames) = fixtures::long_aac(include_bytes!("../tests/fixtures/aac.m4a"), 30);
    let reference = &raw[1024 * 2..(1024 + frames as usize) * 2];
    let mut decoder = open(&bytes, 0);
    assert_eq!(decoder.playable_frames, Some(frames));
    assert_eq!(decode(&mut decoder), reference);
    for position in [3100, 8000, 2100, 0, 12_770] {
        decoder.seek(position).unwrap();
        let actual = decode(&mut decoder);
        let expected = &reference[position as usize * 48 * 2..];
        assert_eq!(
            actual.len(),
            expected.len(),
            "{position}ms retained frame interval"
        );
        // AAC perceptual-noise state can differ after a fresh bounded pre-roll.
        // Require accurate alignment and negligible signal error, not a fixed
        // noise-generator phase from decoding the entire preceding track.
        let error: f64 = actual
            .iter()
            .zip(expected)
            .map(|(&a, &b)| (f64::from(a) - f64::from(b)).powi(2))
            .sum();
        let energy: f64 = expected
            .iter()
            .map(|&sample| f64::from(sample).powi(2))
            .sum();
        assert!(
            error / energy < 1e-6,
            "{position}ms error ratio {}",
            error / energy
        );
        assert_eq!(
            decode(&mut open(&bytes, position)),
            actual,
            "fresh {position}ms"
        );
    }
}

#[test]
fn mp4_without_edits_stays_raw_and_unsupported_edits_fail_explicitly() {
    let original = include_bytes!("../tests/fixtures/aac.m4a");
    let edit = original
        .windows(4)
        .position(|bytes| bytes == b"elst")
        .unwrap();
    let mut legacy = original.to_vec();
    legacy[edit..edit + 4].copy_from_slice(b"free");
    assert_eq!(decode(&mut open(&legacy, 0)).len(), 20_480 * 2);
    for (offset, replacement) in [
        (edit + 8, 2u32.to_be_bytes()),     // multiple edits
        (edit + 16, (-1i32).to_be_bytes()), // an empty edit
        (edit + 20, 0u32.to_be_bytes()),    // non-unit playback rate
    ] {
        let mut invalid = original.to_vec();
        invalid[offset..offset + 4].copy_from_slice(&replacement);
        let error = open_source(Box::new(Cursor::new(invalid)), Hint::new(), 0)
            .err()
            .unwrap();
        assert!(error.contains("presentation"), "{error}");
    }
}

#[test]
fn alac_identity_and_nonzero_unit_rate_edits_preserve_lossless_samples() {
    let reference = decode(&mut open(include_bytes!("../tests/fixtures/tone.wav"), 0));
    let original = include_bytes!("../tests/fixtures/alac.m4a");
    assert_eq!(decode(&mut open(original, 0)), reference);
    let mut edited = original.to_vec();
    let edit = edited
        .windows(4)
        .position(|bytes| bytes == b"elst")
        .unwrap();
    edited[edit + 12..edit + 16].copy_from_slice(&390u32.to_be_bytes());
    edited[edit + 16..edit + 20].copy_from_slice(&480u32.to_be_bytes());
    let mut decoder = open(&edited, 0);
    assert_eq!(decoder.playable_frames, Some(18_720));
    assert_eq!(decode(&mut decoder), reference[480 * 2..]);
    decoder.seek(200).unwrap();
    assert_eq!(decode(&mut decoder), reference[(480 + 9600) * 2..]);
}
