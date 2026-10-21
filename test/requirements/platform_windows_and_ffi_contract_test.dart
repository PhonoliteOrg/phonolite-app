import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('windows platform source contracts', () {
    test('windows runner preserves product name size and dark window behavior', () {
      final topLevel = readProjectModule('windows/CMakeLists.txt');
      final runner = readProjectModule('windows/runner/CMakeLists.txt');
      final mainSource = readProjectModule('windows/runner/main.cpp');
      final win32Source = readProjectModule('windows/runner/ui/shell/win32_window.cpp');

      expectContainsAll(topLevel, const [
        'project(Phonolite LANGUAGES CXX)',
        'set(BINARY_NAME "Phonolite")',
        'native_assets/windows/',
      ]);
      expectContainsAll(runner, const [
        r'add_executable(${BINARY_NAME} WIN32',
        r'target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)',
      ]);
      expectContainsAll(mainSource, const [
        'const WindowPoint origin{10, 10};',
        'const WindowSize size{1280, 720};',
        'if (!window.create(L"Phonolite", origin, size))',
      ]);
      expectContainsAll(win32Source, const [
        'DWMWA_USE_IMMERSIVE_DARK_MODE',
        'AppsUseLightTheme',
        'DwmSetWindowAttribute',
      ]);
    });

    test('local audio decoder is bundled through the Windows FFI plugin', () {
      final pubspec = readProjectModule('pubspec.yaml');
      final pluginPubspec = readProjectModule('packages/phonolite_local_audio/pubspec.yaml');
      final cmake = readProjectModule('packages/phonolite_local_audio/windows/CMakeLists.txt');

      expectContainsAll(pubspec, const [
        'connectivity_plus: ^6.1.5',
        'phonolite_local_audio:',
        'path: packages/phonolite_local_audio',
      ]);
      expect(pubspec, isNot(contains('just_audio_windows:')));
      expectContainsAll(pluginPubspec, const ['name: phonolite_local_audio', 'windows:', 'ffiPlugin: true']);
      expectContainsAll(cmake, const [
        'project(phonolite_local_audio_library LANGUAGES C)',
        'native/local_audio',
        'cargo build',
        'phonolite_local_audio.dll',
        'phonolite_local_audio_bundled_libraries',
      ]);
    });
  });

  group('ffi and transport source contracts', () {
    test('opus wrapper preserves header parsing and decoder constraints', () {
      final dartSource = readProjectModule('packages/phonolite_opus/lib/phonolite_opus.dart');
      final cSource = readProjectModule('packages/phonolite_opus/src/phonolite_opus.c');
      final header = readProjectModule('packages/phonolite_opus/src/phonolite_opus.h');

      expectContainsAll(dartSource, const [
        "'OPUSR01\\u0000'",
        'unsupported opus raw header version',
        'invalid opus raw header lengths',
        'sampleRate == 8000 ||',
        'sampleRate == 48000;',
        "return ffi.DynamicLibrary.open('libphonolite_opus.so');",
        "return ffi.DynamicLibrary.open('phonolite_opus.dll');",
      ]);
      expectContainsAll(cSource, const ['opus_decoder_create', 'opus_decode', 'return 5760;']);
      expectContainsAll(header, const [
        'phonolite_opus_decoder_create',
        'phonolite_opus_decode',
        'phonolite_opus_max_frame_size',
      ]);
    });

    test('quic client preserves transport configuration and ffi surface', () {
      final dartSource = readProjectModule('packages/phonolite_quic/lib/phonolite_quic.dart');
      final rustSource = readProjectModule('packages/phonolite_quic/native/quic_client/src/lib.rs');
      final cargo = readProjectModule('packages/phonolite_quic/native/quic_client/Cargo.toml');
      final header = readProjectModule('packages/phonolite_quic/src/phonolite_quic.h');

      expectContainsAll(dartSource, const [
        "return ffi.DynamicLibrary.open('libphonolite_quic.so');",
        "return ffi.DynamicLibrary.open('phonolite_quic.dll');",
        'int openTrack({',
        'void sendBufferStats({',
        'void sendPlayback({',
        'int seek({',
        'int get requestId',
        'void suspendAudio()',
        'Map<String, Object?>? pollEvent()',
        'int? pollRttMs()',
      ]);
      expectContainsAll(rustSource, const [
        'const ALPN_QUIC: &[&[u8]] = &[b"phonolite-quic"];',
        'const MAX_DELIVERY_BYTES: usize = 512 * 1024;',
        'config.verify_peer(false);',
        'config.set_max_idle_timeout(30_000);',
        'const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(10);',
        'if last_ping.elapsed() >= KEEPALIVE_INTERVAL',
        'ClientMessage::Auth { token: &token }',
        'ControlCommand::Seek',
        'ControlCommand::Advance',
        'ControlCommand::SuspendAudio',
        'source_version: Option<String>',
        'range_end_ms: Option<u32>',
        'end_of_track: Option<bool>',
      ]);
      expectContainsAll(cargo, const [
        'quiche = { version = "0.20", default-features = false, features = ["boringssl-vendored"] }',
      ]);
      expectContainsAll(header, const [
        'phonolite_quic_connect',
        'phonolite_quic_open_track',
        'phonolite_quic_open_track_at',
        'phonolite_quic_send_buffer',
        'phonolite_quic_send_playback',
        'phonolite_quic_seek',
        'phonolite_quic_suspend_audio',
        'phonolite_quic_generation',
        'phonolite_quic_poll_event',
        'phonolite_quic_poll_rtt_ms',
      ]);
    });

    test('local audio decoder exposes MP3 FLAC PCM and seek ffi surface', () {
      final dartSource = readProjectModule('packages/phonolite_local_audio/lib/phonolite_local_audio.dart');
      final rustSource = readProjectModule('packages/phonolite_local_audio/native/local_audio/src/lib.rs');
      final cargo = readProjectModule('packages/phonolite_local_audio/native/local_audio/Cargo.toml');
      final header = readProjectModule('packages/phonolite_local_audio/src/phonolite_local_audio.h');

      expectContainsAll(dartSource, const [
        'class LocalAudioDecoder',
        'factory LocalAudioDecoder.open(',
        'int readInto(Int16List buffer)',
        'Duration seek(Duration position)',
        "return ffi.DynamicLibrary.open('libphonolite_local_audio.so');",
        "return ffi.DynamicLibrary.open('phonolite_local_audio.dll');",
      ]);
      expectContainsAll(rustSource, const [
        'SampleBuffer::<i16>',
        'SeekMode::Coarse',
        'pending_skip_frames',
        'phonolite_local_audio_open',
        'phonolite_local_audio_read',
        'phonolite_local_audio_seek',
        'phonolite_local_audio_last_error',
        'phonolite_local_audio_close',
      ]);
      expectContainsAll(cargo, const [
        'symphonia',
        'features = ["mp3", "flac"]',
        'crate-type = ["cdylib", "staticlib"]',
      ]);
      expectContainsAll(header, const [
        'phonolite_local_audio_open',
        'phonolite_local_audio_read',
        'phonolite_local_audio_seek',
        'phonolite_local_audio_sample_rate',
        'phonolite_local_audio_channels',
        'phonolite_local_audio_duration_ms',
        'phonolite_local_audio_position_ms',
        'phonolite_local_audio_close',
      ]);
    });
  });
}
