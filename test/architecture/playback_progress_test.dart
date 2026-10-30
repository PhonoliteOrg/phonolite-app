import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

void main() {
  AudioPlaybackHarness session(MemoryQuic transport, {bool paused = false}) => AudioPlaybackHarness(
    transport: transport,
    decoderFactory: MemoryOpusDecoder.new,
    outputFactory: (_, __, ___) => MemoryPcmOutput(),
    initialPaused: paused,
    transportProgressTimeout: const Duration(milliseconds: 150),
  );

  bool stopped(AudioPlaybackHarness player) =>
      player.messages.any((event) => event['type'] == 'state' && event['active'] == false);

  test('a connected Opus source without bytes fails recoverably', () async {
    final transport = MemoryQuic();
    final player = session(transport);
    addTearDown(player.close);
    player.start();
    await waitUntil(() => stopped(player));
    expect(transport.closed, isTrue);
    expect(player.messages.any((event) => event['source_rejected'] == true), isFalse);
    expect(player.messages.where((event) => event['type'] == 'complete'), isEmpty);
  });

  for (final failure in [
    'stream cache capacity exhausted; retry playback',
    'server shutting down',
    'stream capacity unavailable: StreamLimit',
  ]) {
    test('Opus server admission failure is recoverable: $failure', () async {
      final transport = MemoryQuic();
      transport.onRequest = (_, __) => transport.events.add({
        'type': 'error',
        'origin': 'server',
        'request_id': transport.requestId,
        'message': failure,
      });
      final player = session(transport);
      addTearDown(player.close);
      player.start();
      await waitUntil(() => stopped(player));
      expect(player.messages.any((event) => event['source_rejected'] == true), isFalse);
    });
  }

  test('Opus source rejection still prevents retrying an invalid track', () async {
    final transport = MemoryQuic();
    transport.onRequest = (_, __) => transport.events.add({
      'type': 'error',
      'origin': 'server',
      'request_id': transport.requestId,
      'message': 'track not found',
    });
    final player = session(transport);
    addTearDown(player.close);
    player.start();
    await waitUntil(() => stopped(player));
    expect(player.messages.any((event) => event['source_rejected'] == true), isTrue);
  });

  test('a fresh seek gets its own delivery deadline', () async {
    final transport = MemoryQuic();
    final player = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => MemoryPcmOutput(),
      transportProgressTimeout: const Duration(milliseconds: 350),
    );
    addTearDown(player.close);
    player.start();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final seeking = player.seek(const Duration(seconds: 20));
    await waitUntil(() => transport.requestedPositions.length == 2);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(stopped(player), isFalse);
    transport.deliverRange(startMs: 20000, endMs: 25000, seekId: 1);
    expect(await seeking, isTrue);
  });

  test('paused Opus does not expire and a resumed silent source does', () async {
    final transport = MemoryQuic();
    final player = session(transport, paused: true);
    addTearDown(player.close);
    player.start();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(stopped(player), isFalse);
    expect(transport.closed, isFalse);
    player.resume();
    await waitUntil(() => stopped(player));
  });

  test('ongoing Opus byte progress renews the delivery deadline', () async {
    final transport = MemoryQuic();
    transport.onRequest = (_, __) => transport.deliverRange(startMs: 0, endMs: 10000, complete: false, packetCount: 0);
    final player = session(transport);
    addTearDown(player.close);
    player.start();
    final producer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => transport.chunks.add(Uint8List.fromList([1, 0, 7])),
    );
    addTearDown(producer.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(stopped(player), isFalse);
    expect(player.cachedBytes, greaterThan(5));
    producer.cancel();
    await waitUntil(() => stopped(player));
  });
}
