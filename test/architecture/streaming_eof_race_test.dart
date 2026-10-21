import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  test(
    'seek flush failure resolves as failed and retires the session',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start + 10000,
        seekId: seekId,
      );
      final output = MemoryPcmOutput()
        ..flushCheck = () async => throw StateError('Output flush failed');
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => output,
        initialPaused: true,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedBytes > 100);

      expect(
        await session
            .seek(const Duration(seconds: 20))
            .timeout(const Duration(seconds: 2)),
        isFalse,
      );
      await waitUntil(
        () => session.messages.any(
          (event) => event['type'] == 'state' && event['active'] == false,
        ),
      );
      expect(output.disposed, isTrue);
      expect(
        session.messages.where((event) => event['type'] == 'complete'),
        isEmpty,
      );
    },
  );

  test(
    'closing during a seek flush cannot reopen the retired output',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start + 10000,
        seekId: seekId,
      );
      final flush = Completer<void>();
      final output = MemoryPcmOutput()..flushCheck = () => flush.future;
      var opens = 0;
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) {
          opens++;
          return output;
        },
        initialPaused: true,
      );
      addTearDown(() async {
        if (!flush.isCompleted) flush.complete();
        await session.close();
      });
      session.start();
      await waitUntil(() => session.cachedBytes > 100);
      final seek = session.seek(const Duration(seconds: 20));
      await waitUntil(() => output.flushes == 1);
      // Let the replacement header reach the decoder's pending output reset.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final close = session.close();
      expect(output.disposed, isTrue);
      flush.complete();
      await close.timeout(const Duration(seconds: 2));

      expect(await seek, isFalse);
      expect(opens, 1);
      expect(
        session.messages.where((event) => event['type'] == 'complete'),
        isEmpty,
      );
    },
  );

  test(
    'a seek retires pending EOF idle checks without finishing the track',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: 500,
        durationMs: 500,
        seekId: seekId,
        endOfTrack: true,
      );
      final idleChecks = <Completer<bool>>[];
      final output = MemoryPcmOutput()
        ..idleCheck = () {
          final result = Completer<bool>();
          idleChecks.add(result);
          return result.future;
        };
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => output,
      );
      addTearDown(() async {
        for (final check in idleChecks) {
          if (!check.isCompleted) check.complete(true);
        }
        await session.close();
      });
      session.start();
      // Both the pump drain and final-range decoder wait for native idleness.
      await waitUntil(() => idleChecks.length >= 2);
      session.pause();
      final seek = session.seek(const Duration(milliseconds: 100));
      await waitUntil(() => output.flushes == 1);
      output.idleCheck = null;
      for (final check in idleChecks) {
        check.complete(true);
      }

      expect(await seek.timeout(const Duration(seconds: 2)), isTrue);
      expect(session.paused, isTrue);
      expect(transport.requestedPositions, [0]);
      expect(
        session.messages.where((event) => event['type'] == 'complete'),
        isEmpty,
      );
      expect(output.disposed, isFalse);
    },
  );
}
