use std::ffi::c_void;
use std::io::{Read, Seek, SeekFrom};
use std::sync::{atomic::AtomicBool, Arc, Mutex};

use symphonia::core::io::MediaSource;

use crate::quic_source::QuicSource;
use crate::{
    failure_code, phonolite_local_audio_open_quic, tests::verbatim_flac, LocalAudioHandle,
};

const WINDOW: usize = 256 * 1024;

#[derive(Default)]
struct Observations {
    requests: Vec<(u64, usize, u32)>,
    closed: usize,
    failure: i32,
    empty: bool,
    maximum_fill: Option<usize>,
    different_length: bool,
    fail_on_request: Option<usize>,
}

struct MemorySource {
    bytes: Vec<u8>,
    observations: Arc<Mutex<Observations>>,
}

unsafe extern "C" fn read_range(
    handle: *mut c_void,
    offset: u64,
    output: *mut u8,
    capacity: usize,
    timeout_ms: u32,
    total: *mut u64,
) -> i64 {
    let source = &mut *handle.cast::<MemorySource>();
    let mut observed = source.observations.lock().unwrap();
    observed.requests.push((offset, capacity, timeout_ms));
    if observed
        .fail_on_request
        .is_some_and(|request| observed.requests.len() >= request)
    {
        observed.failure = -102;
    }
    if observed.failure != 0 {
        return i64::from(observed.failure);
    }
    *total = source.bytes.len() as u64 + u64::from(observed.different_length);
    let start = (offset as usize).min(source.bytes.len());
    let mut count = capacity.min(source.bytes.len() - start);
    if observed.empty {
        count = 0;
    }
    if let Some(maximum) = observed.maximum_fill {
        count = count.min(maximum);
    }
    std::ptr::copy_nonoverlapping(source.bytes.as_ptr().add(start), output, count);
    count as i64
}

unsafe extern "C" fn error_code(handle: *mut c_void) -> i32 {
    (*handle.cast::<MemorySource>())
        .observations
        .lock()
        .unwrap()
        .failure
}

unsafe extern "C" fn copy_error(_handle: *mut c_void, output: *mut u8, capacity: usize) -> usize {
    let message = b"memory QUIC source failed";
    let count = message.len().min(capacity);
    std::ptr::copy_nonoverlapping(message.as_ptr(), output, count);
    count
}

unsafe extern "C" fn close(handle: *mut c_void) {
    let source = Box::from_raw(handle.cast::<MemorySource>());
    source.observations.lock().unwrap().closed += 1;
}

fn descriptor(bytes: Vec<u8>, observations: &Arc<Mutex<Observations>>) -> *mut c_void {
    Box::into_raw(Box::new(MemorySource {
        bytes,
        observations: Arc::clone(observations),
    }))
    .cast()
}

fn open_source(
    bytes: Vec<u8>,
    observations: &Arc<Mutex<Observations>>,
) -> Result<QuicSource, String> {
    unsafe {
        QuicSource::open(
            descriptor(bytes, observations),
            Some(read_range),
            Some(error_code),
            Some(copy_error),
            Some(close),
            Arc::new(AtomicBool::new(false)),
        )
    }
}

#[test]
fn bounded_source_ranges_seek_by_byte_offset_and_close_once() {
    let observations = Arc::new(Mutex::new(Observations::default()));
    let bytes: Vec<u8> = (0..WINDOW * 3 + 19)
        .map(|index| (index % 251) as u8)
        .collect();
    let mut source = open_source(bytes.clone(), &observations).unwrap();
    assert_eq!(source.byte_len(), Some(bytes.len() as u64));
    assert!(source.is_seekable());
    let mut output = [0; 37];
    source.read_exact(&mut output).unwrap();
    assert_eq!(output, bytes[..37]);
    assert_eq!(observations.lock().unwrap().requests.len(), 1);

    source
        .seek(SeekFrom::Start((WINDOW * 2 + 17) as u64))
        .unwrap();
    source.read_exact(&mut output).unwrap();
    assert_eq!(output, bytes[WINDOW * 2 + 17..WINDOW * 2 + 54]);
    source.seek(SeekFrom::End(-9)).unwrap();
    let mut tail = [0; 9];
    source.read_exact(&mut tail).unwrap();
    assert_eq!(tail, bytes[bytes.len() - 9..]);
    assert_eq!(source.read(&mut tail).unwrap(), 0);
    assert!(source.seek(SeekFrom::Start(0)).is_ok());
    assert!(source.seek(SeekFrom::Current(-1)).is_err());
    drop(source);
    let observed = observations.lock().unwrap();
    assert_eq!(observed.closed, 1);
    assert!(observed
        .requests
        .iter()
        .all(|(_, length, timeout)| *length <= WINDOW && *timeout > 0 && *timeout <= 5000));
    assert_eq!(observed.requests[0].1, 16 * 1024);
}

#[test]
fn sequential_decoder_windows_form_one_contiguous_span_then_uncached_seeks_restart_offsets() {
    let observations = Arc::new(Mutex::new(Observations::default()));
    let bytes: Vec<u8> = (0..WINDOW * 7 + 137)
        .map(|index| (index.wrapping_mul(19) % 251) as u8)
        .collect();
    let mut source = open_source(bytes.clone(), &observations).unwrap();
    let mut full = Vec::new();
    source.read_to_end(&mut full).unwrap();
    assert_eq!(full, bytes);
    let offsets: Vec<u64> = observations
        .lock()
        .unwrap()
        .requests
        .iter()
        .map(|(offset, _, _)| *offset)
        .collect();
    assert_eq!(offsets.first(), Some(&0));
    let observed = observations.lock().unwrap();
    for pair in observed.requests.windows(2) {
        assert_eq!(pair[1].0, pair[0].0 + pair[0].1 as u64);
    }
    drop(observed);

    let mut output = [0; 73];
    for offset in [WINDOW * 2 + 17, WINDOW * 5 + 31, 13] {
        let before = observations.lock().unwrap().requests.len();
        source.seek(SeekFrom::Start(offset as u64)).unwrap();
        source.read_exact(&mut output).unwrap();
        assert_eq!(output, bytes[offset..offset + output.len()]);
        assert_eq!(observations.lock().unwrap().requests.len(), before + 1);
        assert_eq!(
            observations.lock().unwrap().requests.last().unwrap().0,
            offset as u64
        );

        // An adjacent read keeps consuming the same decoder window.
        source.read_exact(&mut output).unwrap();
        assert_eq!(output, bytes[offset + 73..offset + 146]);
        assert_eq!(observations.lock().unwrap().requests.len(), before + 1);
    }
    drop(source);
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn opening_failure_closes_transport_and_preserves_transient_classification() {
    let observations = Arc::new(Mutex::new(Observations {
        failure: -102,
        ..Default::default()
    }));
    assert!(open_source(vec![1; 100], &observations).is_err());
    assert_eq!(
        failure_code(),
        -103,
        "transport failures must remain reconnectable"
    );
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn zero_progress_before_eof_and_changed_lengths_are_source_failures() {
    let observations = Arc::new(Mutex::new(Observations {
        empty: true,
        ..Default::default()
    }));
    assert!(open_source(vec![1; 100], &observations).is_err());
    assert_eq!(failure_code(), -102);
    assert_eq!(observations.lock().unwrap().closed, 1);

    let observations = Arc::new(Mutex::new(Observations::default()));
    let mut source = open_source(vec![1; WINDOW * 2], &observations).unwrap();
    observations.lock().unwrap().different_length = true;
    source.seek(SeekFrom::Start(WINDOW as u64)).unwrap();
    assert!(source.read(&mut [0; 1]).is_err());
    assert_eq!(failure_code(), -102);
    drop(source);
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn positive_short_fills_preserve_contiguous_bytes_seek_and_real_eof() {
    let observations = Arc::new(Mutex::new(Observations {
        maximum_fill: Some(37),
        ..Default::default()
    }));
    let bytes: Vec<u8> = (0..5003).map(|index| (index % 251) as u8).collect();
    let mut source = open_source(bytes.clone(), &observations).unwrap();
    assert_eq!(observations.lock().unwrap().requests[0].1, 16 * 1024);
    let mut actual = Vec::new();
    source.read_to_end(&mut actual).unwrap();
    assert_eq!(actual, bytes);
    assert_eq!(source.read(&mut [0; 1]).unwrap(), 0);
    let requests = observations.lock().unwrap().requests.clone();
    assert!(requests.windows(2).all(|pair| pair[1].0 == pair[0].0 + 37));
    source.seek(SeekFrom::Start(13)).unwrap();
    let mut output = [0; 51];
    source.read_exact(&mut output).unwrap();
    assert_eq!(output, bytes[13..64]);
    drop(source);
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn quic_flac_decoding_and_seeking_preserve_every_24_and_32_bit_sample() {
    for bits in [24, 32] {
        let values: Vec<i32> = (0..4096).map(|index| index * 131 - 200_001).collect();
        let bytes = verbatim_flac(192_000, bits, &values);
        let observations = Arc::new(Mutex::new(Observations::default()));
        let raw = unsafe {
            phonolite_local_audio_open_quic(
                descriptor(bytes, &observations),
                Some(read_range),
                Some(error_code),
                Some(copy_error),
                Some(close),
                0,
            )
        };
        assert!(!raw.is_null());
        let mut decoder = unsafe { Box::from_raw(raw) };
        assert_eq!(decoder.sample_rate, 192_000);
        assert_eq!(decoder.bit_depth, bits);
        let expected: Vec<i32> = values.iter().map(|sample| sample << (32 - bits)).collect();
        assert_eq!(decode_all(&mut decoder), expected);
        assert_eq!(decoder.seek(5).unwrap(), 5);
        assert_eq!(decode_all(&mut decoder), expected[960..]);
        assert_eq!(decoder.seek(0).unwrap(), 0);
        assert_eq!(decode_all(&mut decoder), expected);
        drop(decoder);
        assert_eq!(observations.lock().unwrap().closed, 1);
    }
}

#[test]
fn unsupported_audio_closes_the_consumed_source_handle() {
    let observations = Arc::new(Mutex::new(Observations::default()));
    let raw = unsafe {
        phonolite_local_audio_open_quic(
            descriptor(b"not an audio source".to_vec(), &observations),
            Some(read_range),
            Some(error_code),
            Some(copy_error),
            Some(close),
            0,
        )
    };
    assert!(raw.is_null());
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn source_quic_decodes_and_seeks_server_supported_file_formats() {
    for (name, bytes) in [
        (
            "aac.m4a",
            include_bytes!("../tests/fixtures/aac.m4a").as_slice(),
        ),
        (
            "alac.m4a",
            include_bytes!("../tests/fixtures/alac.m4a").as_slice(),
        ),
        (
            "tone.aac",
            include_bytes!("../tests/fixtures/tone.aac").as_slice(),
        ),
        (
            "vorbis.ogg",
            include_bytes!("../tests/fixtures/vorbis.ogg").as_slice(),
        ),
        (
            "tone.wav",
            include_bytes!("../tests/fixtures/tone.wav").as_slice(),
        ),
        (
            "tone.aiff",
            include_bytes!("../tests/fixtures/tone.aiff").as_slice(),
        ),
    ] {
        let observations = Arc::new(Mutex::new(Observations::default()));
        let raw = unsafe {
            phonolite_local_audio_open_quic(
                descriptor(bytes.to_vec(), &observations),
                Some(read_range),
                Some(error_code),
                Some(copy_error),
                Some(close),
                0,
            )
        };
        assert!(
            !raw.is_null(),
            "{name} must open through the QUIC source: {:?}",
            crate::LAST_ERROR.with(|slot| slot.borrow().clone())
        );
        let mut decoder = unsafe { Box::from_raw(raw) };
        assert_eq!(decoder.sample_rate, 48_000, "{name}");
        assert_eq!(decoder.output_channels, 2, "{name}");
        let full = decode_all(&mut decoder);
        assert!(!full.is_empty(), "{name}");
        assert!(full.iter().any(|sample| *sample != 0), "{name}");
        decoder
            .seek(10)
            .unwrap_or_else(|error| panic!("{name}: {error}"));
        assert!(!decode_all(&mut decoder).is_empty(), "{name}");
        drop(decoder);
        assert_eq!(observations.lock().unwrap().closed, 1, "{name}");
    }
}

fn decode_all(decoder: &mut LocalAudioHandle) -> Vec<i32> {
    let mut samples = Vec::new();
    let mut output = [0; 137];
    loop {
        let count = decoder.read32(&mut output).unwrap();
        if count == 0 {
            return samples;
        }
        samples.extend_from_slice(&output[..count]);
    }
}

#[test]
fn decoder_read_and_seek_share_one_deadline_across_positive_partial_fills() {
    unsafe extern "C" fn slow_read(
        handle: *mut c_void,
        offset: u64,
        output: *mut u8,
        capacity: usize,
        timeout_ms: u32,
        total: *mut u64,
    ) -> i64 {
        let slow = (*handle.cast::<MemorySource>())
            .observations
            .lock()
            .unwrap()
            .maximum_fill
            .is_some();
        if slow {
            std::thread::sleep(std::time::Duration::from_millis(8));
        }
        read_range(handle, offset, output, capacity, timeout_ms, total)
    }
    let observations = Arc::new(Mutex::new(Observations::default()));
    let raw = unsafe {
        phonolite_local_audio_open_quic(
            descriptor(
                include_bytes!("../tests/fixtures/tone.wav").to_vec(),
                &observations,
            ),
            Some(slow_read),
            Some(error_code),
            Some(copy_error),
            Some(close),
            0,
        )
    };
    assert!(!raw.is_null());
    let mut decoder = unsafe { Box::from_raw(raw) };
    decoder.seek(200).unwrap();
    observations.lock().unwrap().maximum_fill = Some(64);
    let before = observations.lock().unwrap().requests.len();
    let started = std::time::Instant::now();
    {
        let _budget =
            crate::quic_source::OperationGuard::with_timeout(std::time::Duration::from_millis(35));
        let error = decoder.read32(&mut [0; 4608]).unwrap_err();
        assert!(error.contains("timed out"), "{error}");
        assert_eq!(failure_code(), -103);
        assert!(decoder.seek(0).unwrap_err().contains("timed out"));
    }
    assert!(started.elapsed() < std::time::Duration::from_millis(250));
    let requests = observations.lock().unwrap().requests[before..].to_vec();
    assert!(requests.len() >= 2);
    assert!(requests.windows(2).all(|pair| pair[1].2 <= pair[0].2));
    assert!(requests.iter().all(|request| request.2 <= 35));
    observations.lock().unwrap().maximum_fill = None;
    decoder.seek(0).unwrap();
    assert!(decoder.read32(&mut [0; 64]).unwrap() > 0);
    drop(decoder);
    assert_eq!(observations.lock().unwrap().closed, 1);
}

#[test]
fn interrupted_packet_reads_recover_through_a_fresh_seek_for_each_source_container() {
    let mut mp3 = include_bytes!("../tests/fixtures/tone.mp3").repeat(60);
    // Repeated raw MP3 frames have no whole-file Xing/LAME trim declaration.
    for index in 0..mp3.len().saturating_sub(4) {
        if &mp3[index..index + 4] == b"Xing" || &mp3[index..index + 4] == b"Info" {
            mp3[index..index + 4].fill(0);
        }
    }
    let values: Vec<i32> = (0..32000).map(|index| index * 131 - 200_001).collect();
    let (aac, _) =
        crate::seek_tests::fixtures::long_aac(include_bytes!("../tests/fixtures/aac.m4a"), 30);
    let vorbis =
        crate::seek_tests::fixtures::long_vorbis(include_bytes!("../tests/fixtures/vorbis.ogg"));
    for (name, bytes) in [
        ("flac", verbatim_flac(48000, 32, &values)),
        ("vorbis", vorbis),
        ("mp4-aac", aac),
        ("mp3", mp3),
        ("wav", include_bytes!("../tests/fixtures/tone.wav").to_vec()),
    ] {
        let mut reference = crate::open_source(
            Box::new(std::io::Cursor::new(bytes.clone())),
            symphonia::core::probe::Hint::new(),
            200,
        )
        .unwrap();
        let expected = decode_all(&mut reference);
        assert!(!expected.is_empty(), "{name}");
        let observations = Arc::new(Mutex::new(Observations::default()));
        let raw = unsafe {
            phonolite_local_audio_open_quic(
                descriptor(bytes, &observations),
                Some(read_range),
                Some(error_code),
                Some(copy_error),
                Some(close),
                0,
            )
        };
        assert!(!raw.is_null(), "{name}");
        let mut decoder = unsafe { Box::from_raw(raw) };
        {
            let mut observed = observations.lock().unwrap();
            observed.maximum_fill = Some(64);
            observed.fail_on_request = Some(observed.requests.len() + 3);
        }
        assert!(
            decoder.read32(&mut vec![0; 2_000_000]).is_err(),
            "{name}: a midpacket error must surface"
        );
        assert_eq!(failure_code(), -103, "{name}: interruption is transient");
        {
            let mut observed = observations.lock().unwrap();
            observed.maximum_fill = None;
            observed.fail_on_request = None;
            observed.failure = 0;
        }
        decoder
            .seek(200)
            .unwrap_or_else(|error| panic!("{name}: {error}"));
        let actual = decode_all(&mut decoder);
        assert_eq!(actual.len(), expected.len(), "{name}: retained PCM suffix");
        if name == "mp4-aac" {
            let error: f64 = actual
                .iter()
                .zip(&expected)
                .map(|(&a, &b)| (f64::from(a) - f64::from(b)).powi(2))
                .sum();
            let energy: f64 = expected
                .iter()
                .map(|&sample| f64::from(sample).powi(2))
                .sum();
            assert!(error / energy < 1e-6, "{name}: recovered alignment");
        } else {
            assert_eq!(actual, expected, "{name}: recovered PCM");
        }
        drop(decoder);
        assert_eq!(observations.lock().unwrap().closed, 1, "{name}");
    }
    // A cancelled remote operation must not reject unrelated local playback on
    // the same native thread. Public entry points clear the thread-local marker.
    let mut local = crate::open_source(
        Box::new(std::io::Cursor::new(
            include_bytes!("../tests/fixtures/tone.wav").to_vec(),
        )),
        symphonia::core::probe::Hint::new(),
        0,
    )
    .unwrap();
    crate::set_failure_code(-103);
    let mut output = [0; 64];
    assert!(
        unsafe {
            crate::phonolite_local_audio_read32(
                local.as_mut(),
                output.as_mut_ptr(),
                output.len() as u64,
            )
        } > 0
    );
    assert_eq!(failure_code(), 0);
}
