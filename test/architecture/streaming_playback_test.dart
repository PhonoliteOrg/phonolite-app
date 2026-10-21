import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  test(
    'paused full PCM buffer accepts uncached seek and reuses output',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start + 10000,
        seekId: seekId,
      );
      final output = MemoryPcmOutput();
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
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedAheadMilliseconds(0) >= 1500);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(await session.seek(const Duration(seconds: 20)), isTrue);
      expect(transport.requestedPositions, [0, 20000]);
      expect(session.paused, isTrue);
      expect(output.writes, 0);
      expect(output.flushes, 1);
      expect(opens, 1);
      session.resume();
      await waitUntil(() => output.writes > 0);
      expect(session.paused, isFalse);
    },
  );

  test('cached paused seek decodes locally without retransmission', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) =>
        transport.deliverRange(startMs: start, endMs: 10000, seekId: seekId);
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: true,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.cachedAheadMilliseconds(1000) >= 200);

    expect(await session.seek(const Duration(seconds: 1)), isTrue);
    expect(transport.requestedPositions, [0]);
    expect(transport.suspensions, 1);
    expect(output.writes, 0);
    session.resume();
    await waitUntil(() => output.writes > 0);
  });

  test(
    'rapid seeks cancel old writes and only newest readiness succeeds',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start + 10000,
        value: start ~/ 1000 + 1,
        seekId: seekId,
      );
      final output = MemoryPcmOutput()..blockWrites = true;
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => output,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedAheadMilliseconds(0) >= 1500);
      final first = session.seek(const Duration(seconds: 20));
      final latest = session.seek(const Duration(seconds: 40));
      expect(await first, isFalse);
      expect(await latest, isTrue);
      output.blockWrites = false;
      await waitUntil(() => output.writes > 0);
      expect(output.values.every((value) => value == 41), isTrue);
      expect(output.disposed, isFalse);
    },
  );

  test(
    'range continuation trims codec padding and keeps one output device',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start + 500,
        durationMs: 1000,
        value: start == 0 ? 1 : 2,
        seekId: seekId,
        endOfTrack: start >= 500,
      );
      final output = MemoryPcmOutput();
      var opens = 0;
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) {
          opens++;
          return output;
        },
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(
        () => session.messages.any((event) => event['type'] == 'complete'),
      );
      expect(transport.requestedPositions, [0, 500]);
      expect(output.samplesWritten, 48000 * 2);
      expect(output.values, containsAll([1, 2]));
      expect(opens, 1);
      expect(output.flushes, 0);
    },
  );

  test('seek during automatic buffering clears automatic pause', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => transport.deliverRange(
      startMs: start,
      endMs: start + 200,
      seekId: seekId,
      complete: false,
    );
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.autoPaused);
    expect(await session.seek(const Duration(seconds: 20)), isTrue);
    expect(session.autoPaused, isFalse);
    expect(session.paused, isFalse);
    expect(output.flushes, 1);
  });

  test(
    'paused EOF can seek again and resume using its cached output',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: 1000,
        durationMs: 1000,
        seekId: seekId,
        endOfTrack: true,
      );
      final output = MemoryPcmOutput();
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => output,
        initialPaused: true,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedAheadMilliseconds(0) == 1000);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await session.seek(const Duration(milliseconds: 800)), isTrue);
      session.resume();
      await waitUntil(
        () => session.messages.any((event) => event['type'] == 'complete'),
      );
      expect(transport.requestedPositions, [0]);
      expect(output.samplesWritten, 200 * 48 * 2);
      expect(output.flushes, 1);
    },
  );

  test('server-clamped endpoint seek becomes ready while paused', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => transport.deliverRange(
      startMs: start >= 1000 ? 999 : start,
      endMs: 1000,
      durationMs: 1000,
      seekId: seekId,
      endOfTrack: true,
    );
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: true,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.cachedAheadMilliseconds(0) == 1000);
    expect(await session.seek(const Duration(seconds: 1)), isTrue);
    expect(session.paused, isTrue);
    session.resume();
    await waitUntil(
      () => session.messages.any((event) => event['type'] == 'complete'),
    );
    expect(transport.requestedPositions, [0, 1000]);
    expect(output.samplesWritten, 48 * 2);
  });

  test(
    'partial cached continuation removes a fractional packet overlap',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) => transport.deliverRange(
        startMs: start,
        endMs: start == 0 ? 1000 : 2000,
        durationMs: 2000,
        seekId: seekId,
        packetCount: start == 0 ? 50 : null,
        complete: start != 0,
        endOfTrack: start != 0,
      );
      final output = MemoryPcmOutput();
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => output,
        initialPaused: true,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedAheadMilliseconds(0) == 993);
      expect(await session.seek(const Duration(milliseconds: 100)), isTrue);
      session.resume();
      await waitUntil(
        () => session.messages.any((event) => event['type'] == 'complete'),
      );
      expect(transport.requestedPositions, [0, 993]);
      expect(output.samplesWritten, 1900 * 48 * 2);
      expect(output.flushes, 1);
    },
  );

  for (final delayContinuationPackets in [false, true]) {
    test(
      delayContinuationPackets
          ? 'abandoned cached successor waits for replacement header packets'
          : 'abandoned cached successor requests its missing continuation',
      () async {
        final transport = MemoryQuic();
        void Function()? releasePackets;
        transport.onRequest = (start, seekId) {
          if (start == 20000) {
            // Seeking away leaves a retained prefix with no live producer.
            transport.deliverRange(
              startMs: start,
              endMs: 25000,
              packetCount: 120,
              complete: false,
              value: 2,
              seekId: seekId,
            );
          } else if (start == 15000) {
            transport.deliverRange(
              startMs: start,
              endMs: 20000,
              value: 1,
              seekId: seekId,
            );
          } else {
            transport.deliverRange(
              startMs: start,
              endMs: 25000,
              value: 3,
              seekId: seekId,
              endOfTrack: true,
            );
            if (delayContinuationPackets) {
              // Receive the replacement header before any of its packets.
              final header = transport.chunks.removeFirst();
              final packets = transport.chunks.toList();
              transport.chunks
                ..clear()
                ..add(header);
              releasePackets = () => transport.chunks.addAll(packets);
            }
          }
        };
        final output = MemoryPcmOutput();
        final session = AudioPlaybackHarness(
          transport: transport,
          decoderFactory: MemoryOpusDecoder.new,
          outputFactory: (_, __, ___) => output,
          initialPaused: true,
          startOffset: const Duration(seconds: 20),
        );
        addTearDown(session.close);
        session.start();
        await waitUntil(() => session.cachedAheadMilliseconds(20000) == 2393);
        expect(await session.seek(const Duration(seconds: 15)), isTrue);
        session.resume();

        if (delayContinuationPackets) {
          await waitUntil(
            () =>
                releasePackets != null &&
                transport.chunks.isEmpty &&
                transport.events.isEmpty,
          );
          // Repeated decode polls must retain the new live producer.
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(transport.requestedPositions, [20000, 15000, 22393]);
          expect(output.values, isNot(contains(3)));
          releasePackets!();
        }

        await waitUntil(
          () => session.messages.any((event) => event['type'] == 'complete'),
        );
        expect(transport.requestedPositions, [20000, 15000, 22393]);
        expect(output.values, containsAll([1, 2, 3]));
        // The half millisecond at the retained prefix boundary is not replayed.
        expect(output.samplesWritten, 10000 * 48 * 2);
        expect(output.flushes, 1);
      },
    );
  }

  test('live producer at track boundary waits for its end marker', () async {
    final transport = MemoryQuic();
    void Function()? finishRange;
    transport.onRequest = (start, seekId) {
      transport.deliverRange(
        startMs: start,
        endMs: 1000,
        durationMs: 1000,
        seekId: seekId,
        endOfTrack: true,
      );
      final endMarker = transport.chunks.removeLast();
      finishRange = () => transport.chunks.add(endMarker);
    };
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.autoPaused);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(output.samplesWritten, 1000 * 48 * 2);
    expect(transport.requestedPositions, [0]);
    expect(
      session.messages.any((event) => event['type'] == 'complete'),
      isFalse,
    );
    finishRange!();
    await waitUntil(
      () => session.messages.any((event) => event['type'] == 'complete'),
    );
    expect(transport.requestedPositions, [0]);
  });

  test(
    'server errors are read even when a paused cache reaches its horizon',
    () async {
      final transport = MemoryQuic();
      transport.onRequest = (start, seekId) =>
          transport.deliverRange(startMs: start, endMs: 10000, seekId: seekId);
      final session = AudioPlaybackHarness(
        transport: transport,
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => MemoryPcmOutput(),
        initialPaused: true,
      );
      addTearDown(session.close);
      session.start();
      await waitUntil(() => session.cachedAheadMilliseconds(0) >= 3000);
      transport.events.add({
        'type': 'error',
        'request_id': transport.requestId,
        'message': 'range unavailable',
      });
      await waitUntil(
        () => session.messages.any(
          (event) => event['type'] == 'state' && event['active'] == false,
        ),
      );
    },
  );
}
