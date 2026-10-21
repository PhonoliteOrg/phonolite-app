import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_local_audio/phonolite_local_audio.dart';

import '../support/streaming_test_helpers.dart';

class _ObservedPcmOutput extends MemoryPcmOutput {
  int writeAttempts = 0;

  @override
  Future<void> write(Int16List samples) async {
    writeAttempts++;
    await super.write(samples);
  }
}

void main() {
  final candidates = [
    'build/windows/x64/plugins/phonolite_local_audio/phonolite_local_audio.dll',
    'build/windows/x64/plugins/phonolite_local_audio/cargo/release/phonolite_local_audio.dll',
    'build/windows/x64/runner/Release/phonolite_local_audio.dll',
  ];
  final libraryPath = Platform.isWindows
      ? candidates.where((path) => File(path).existsSync()).firstOrNull
      : null;
  // Only the decoder is loaded. PCM output remains an in-memory test adapter.
  if (libraryPath != null) {
    ffi.DynamicLibrary.open(File(libraryPath).absolute.path);
  }
  final skip = libraryPath == null
      ? 'Requires a compiled Windows phonolite_local_audio.dll.'
      : false;

  for (final extension in ['flac', 'mp3']) {
    final filePath = File(
      'packages/phonolite_local_audio/native/local_audio/tests/fixtures/tone.$extension',
    ).absolute.path;

    test('$extension EOF idle wait accepts the latest paused seek', () async {
      final idleGate = Completer<bool>();
      var holdIdle = true;
      var idleCalls = 0;
      final output = MemoryPcmOutput()
        ..idleCheck = () {
          idleCalls++;
          return holdIdle ? idleGate.future : Future<bool>.value(true);
        };
      var opens = 0;
      final session = AudioPlaybackHarness.local(
        filePath: filePath,
        outputFactory: (_, __, ___) {
          opens++;
          return output;
        },
      );
      addTearDown(() async {
        if (!idleGate.isCompleted) idleGate.complete(true);
        await session.close();
      });
      session.start();
      await waitUntil(() => idleCalls > 0);
      final writesAtEof = output.writes;
      expect(writesAtEof, greaterThan(0));
      session.pause();
      final superseded = session.seek(const Duration(milliseconds: 50));
      final latest = session.seek(const Duration(milliseconds: 200));
      holdIdle = false;
      idleGate.complete(true);
      expect(await superseded, isFalse);
      expect(await latest.timeout(const Duration(seconds: 2)), isTrue);
      expect(session.paused, isTrue);
      expect(output.writes, writesAtEof);
      expect(output.flushes, 1);
      expect(opens, 1);
      expect(output.disposed, isFalse);
      expect(
        session.messages.where((event) => event['type'] == 'complete'),
        isEmpty,
      );
      session.resume();
      await waitUntil(
        () => session.messages.any((event) => event['type'] == 'complete'),
      );
      expect(output.writes, greaterThan(writesAtEof));
    }, skip: skip);

    test(
      '$extension paused endpoint seek is ready and completes on resume',
      () async {
        final metadata = LocalAudioDecoder.open(filePath);
        final duration = metadata.duration;
        metadata.close();
        expect(duration, greaterThan(Duration.zero));
        final output = MemoryPcmOutput();
        var opens = 0;
        final session = AudioPlaybackHarness.local(
          filePath: filePath,
          initialPaused: true,
          outputFactory: (_, __, ___) {
            opens++;
            return output;
          },
        );
        addTearDown(session.close);
        session.start();
        await waitUntil(
          () => session.messages.any((event) => event['type'] == 'started'),
        );
        expect(
          await session.seek(duration).timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(session.paused, isTrue);
        expect(output.writes, 0);
        expect(output.flushes, 1);
        expect(opens, 1);
        expect(
          session.messages.where((event) => event['type'] == 'complete'),
          isEmpty,
        );
        session.resume();
        await waitUntil(
          () => session.messages.any((event) => event['type'] == 'complete'),
        );
        expect(
          session.messages.where((event) => event['type'] == 'seek_failed'),
          isEmpty,
        );
      },
      skip: skip,
    );

    test(
      '$extension blocked output is cancelled by a paused local seek',
      () async {
        final output = _ObservedPcmOutput()..blockWrites = true;
        var opens = 0;
        final session = AudioPlaybackHarness.local(
          filePath: filePath,
          outputFactory: (_, __, ___) {
            opens++;
            return output;
          },
        );
        addTearDown(session.close);
        session.start();
        await waitUntil(() => output.writeAttempts > 0);
        session.pause();
        expect(
          await session
              .seek(const Duration(milliseconds: 200))
              .timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(session.paused, isTrue);
        expect(output.writes, 0);
        expect(output.flushes, 1);
        expect(opens, 1);
        expect(output.disposed, isFalse);
        output.blockWrites = false;
        session.resume();
        await waitUntil(
          () => session.messages.any((event) => event['type'] == 'complete'),
        );
        expect(output.writes, greaterThan(0));
      },
      skip: skip,
    );
  }
}
