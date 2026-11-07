import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/rules/audio/audio_recovery_policy.dart';
import 'package:phonolite_app/data/structures/audio/audio_network_history.dart';
import 'package:phonolite_app/data/structures/audio/pcm_ring_buffer.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';

import '../support/streaming_test_helpers.dart';

class _RetiredTelemetryQuic extends MemoryQuic {
  @override
  void suspendAudio() {
    if (closed) throw StateError('Transport retired.');
    super.suspendAudio();
  }

  @override
  void sendBufferStats({required int bufferMs, int? targetMs, bool force = false}) {
    if (closed) throw StateError('Transport retired.');
    super.sendBufferStats(bufferMs: bufferMs, targetMs: targetMs, force: force);
  }
}

void main() {
  test('waiting for a continuation header retains reserve while an uncached seek clears it', () async {
    final transport = MemoryQuic();
    final reportOffsets = <int, int>{};
    final seekIds = <int, int?>{};
    transport.onRequest = (position, seekId) {
      if (position == 0) {
        transport.deliverRange(startMs: 0, endMs: 5000, adaptiveRanges: true);
      } else {
        reportOffsets[position] = transport.bufferReports.length;
        seekIds[position] = seekId;
      }
    };
    final output = MemoryPcmOutput()..blockWrites = true;
    final harness = AudioPlaybackHarness(
      transport: transport,
      settings: const StreamSettings(mode: 'auto', quality: 'high'),
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => reportOffsets.containsKey(5000) && transport.bufferReports.length > reportOffsets[5000]!);
    final retainedReport = transport.bufferReports[reportOffsets[5000]!];
    expect(
      retainedReport.$1,
      inInclusiveRange(4900, 5000),
      reason: 'A new range header does not empty accepted audio.',
    );
    expect(retainedReport.$2, 8000);

    final seeking = harness.seek(const Duration(seconds: 20));
    await waitUntil(() => reportOffsets.containsKey(20000) && transport.bufferReports.length > reportOffsets[20000]!);
    expect(
      transport.bufferReports[reportOffsets[20000]!].$1,
      0,
      reason: 'An uncached seek must demand its new position.',
    );
    transport.deliverRange(
      startMs: 20000,
      endMs: 21000,
      seekId: seekIds[20000],
      adaptiveRanges: true,
      endOfTrack: true,
    );
    expect(await seeking, isTrue);
  });

  for (final scenario in [
    (mode: 'auto', paused: false, targetMs: 8000),
    (mode: 'fixed', paused: false, targetMs: 3000),
    (mode: 'auto', paused: true, targetMs: 2000),
  ]) {
    test('loopback read-ahead distinguishes active Auto from pause: $scenario', () async {
      final transport = MemoryQuic();
      transport.onRequest = (position, seekId) =>
          transport.deliverRange(startMs: position, endMs: 10000, packetCount: 30, complete: false);
      final harness = AudioPlaybackHarness(
        transport: transport,
        baseUrl: 'http://127.0.0.1:3000',
        initialPaused: scenario.paused,
        settings: StreamSettings(mode: scenario.mode, quality: 'high'),
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => MemoryPcmOutput(),
      );
      addTearDown(harness.close);
      harness.start();
      await waitUntil(() => transport.bufferReports.isNotEmpty);
      expect(transport.bufferReports.first.$2, scenario.targetMs);
    });
  }

  test('repeated Play during an underrun preserves the refill gate', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) =>
        transport.deliverRange(startMs: start, endMs: 10000, packetCount: 60, complete: false);
    final output = MemoryPcmOutput();
    final harness = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.autoPaused);
    await harness.pause();
    final writes = output.writes;
    for (var i = 0; i < 3; i++) {
      harness.resume();
      expect(harness.autoPaused, isTrue);
      expect(harness.paused, isTrue);
      expect(output.paused, isTrue);
    }
    expect(output.writes, writes);
    transport.chunks.add(
      Uint8List.fromList([
        for (var i = 0; i < 120; i++) ...[1, 0, 1],
      ]),
    );
    await waitUntil(
      () => harness.messages.any((event) => event['text']?.toString().contains('Buffer recovered:') == true),
    );
    await waitUntil(() => output.writes > writes);
  });

  test('a remembered weak connection starts a new source with its larger buffer', () async {
    final history = AudioNetworkHistory()..remember('http://test.local:3000|null|', 2);
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) =>
        transport.deliverRange(startMs: 0, endMs: 10000, packetCount: 30, complete: false);
    final output = MemoryPcmOutput();
    final harness = AudioPlaybackHarness(
      transport: transport,
      networkHistory: history,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(
      () => harness.messages.any((event) => event['text']?.toString().contains('prebuffer=2.0s') == true),
    );
    expect(output.samplesWritten, 0);
    transport.chunks.add(
      Uint8List.fromList([
        for (var i = 0; i < 120; i++) ...[1, 0, 1],
      ]),
    );
    await waitUntil(() => output.samplesWritten > 0);
    expect(history.levelFor('http://test.local:3000|null|'), 2);
  });

  for (final scenario in [
    (mode: 'auto', negotiated: true, bitrateBps: 96000, accepted: true),
    (mode: 'auto', negotiated: true, bitrateBps: 128000, accepted: false),
    (mode: 'auto', negotiated: false, bitrateBps: 96000, accepted: false),
    (mode: 'fixed', negotiated: true, bitrateBps: 96000, accepted: false),
  ]) {
    test(
      'range bitrate change mode=${scenario.mode} negotiated=${scenario.negotiated} bitrate=${scenario.bitrateBps}',
      () async {
        final transport = MemoryQuic();
        transport.onRequest = (start, seekId) {
          transport.deliverRange(
            startMs: start,
            endMs: start == 0 ? 400 : 800,
            durationMs: 800,
            seekId: seekId,
            endOfTrack: start != 0,
            bitrateBps: start == 0 ? 160000 : scenario.bitrateBps,
            adaptiveRanges: scenario.negotiated,
          );
        };
        final output = MemoryPcmOutput();
        final harness = AudioPlaybackHarness(
          transport: transport,
          settings: StreamSettings(mode: scenario.mode, quality: 'high'),
          decoderFactory: MemoryOpusDecoder.new,
          outputFactory: (_, __, ___) => output,
        );
        addTearDown(harness.close);
        harness.start();
        await waitUntil(
          () => harness.messages.any((event) => event['type'] == 'complete' || event['source_rejected'] == true),
        );
        if (scenario.accepted) {
          expect(harness.messages.any((event) => event['type'] == 'complete'), isTrue);
          expect(output.samplesWritten, 38400 * 2);
          expect(output.flushes, 0);
        } else {
          expect(harness.messages.any((event) => event['source_rejected'] == true), isTrue);
        }
      },
    );
  }

  test('each rapid seek gets its own stall deadline before reconnecting', () async {
    final transport = MemoryQuic();
    int? latestSeekId;
    transport.onRequest = (start, seekId) {
      latestSeekId = seekId;
      if (start == 0) {
        transport.deliverRange(startMs: 0, endMs: 10000, packetCount: 30, complete: false);
      }
    };
    final output = MemoryPcmOutput();
    var replacements = 0;
    final harness = AudioPlaybackHarness(
      transport: transport,
      connectionFactory: () {
        replacements++;
        throw StateError('The current seek is still within its delivery deadline.');
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => output.writes > 0);

    final obsolete = harness.seek(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final latest = harness.seek(const Duration(seconds: 40));
    expect(await obsolete, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(replacements, 0);

    transport.deliverRange(startMs: 40000, endMs: 41000, seekId: latestSeekId, endOfTrack: true);
    expect(await latest, isTrue);
    expect(output.flushes, 2);
  });

  test('partial Opus delivery reconnects at the gap with one output and exact frame count', () async {
    final first = MemoryQuic();
    first.onRequest = (start, seekId) {
      first.deliverRange(startMs: start, endMs: 400, durationMs: 400, packetCount: 10, complete: false);
      first.closed = true;
    };
    final replacement = MemoryQuic();
    replacement.onRequest = (start, seekId) =>
        replacement.deliverRange(startMs: start, endMs: 400, durationMs: 400, endOfTrack: true);
    final output = MemoryPcmOutput();
    var outputs = 0;
    var connections = 0;
    final harness = AudioPlaybackHarness(
      transport: first,
      connectionFactory: () {
        connections++;
        return replacement;
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) {
        outputs++;
        return output;
      },
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.messages.any((event) => event['type'] == 'complete'));
    expect(connections, 1);
    expect(replacement.requestedPositions, <int>[193]);
    expect(output.samplesWritten, 19200 * 2);
    expect(outputs, 1);
    expect(output.flushes, 0);
    expect(harness.messages.where((event) => event['type'] == 'started'), hasLength(1));
    expect(harness.messages.where((event) => event['type'] == 'complete'), hasLength(1));
    expect(replacement.bufferReports, isNotEmpty);
  });

  test('replacement rejects changed source before joining retained audio', () async {
    final first = MemoryQuic();
    first.onRequest = (start, seekId) {
      first.deliverRange(startMs: 0, endMs: 400, packetCount: 10, complete: false);
      first.closed = true;
    };
    final replacement = MemoryQuic();
    replacement.onRequest = (start, seekId) {
      replacement.deliverRange(startMs: start, endMs: 400, endOfTrack: true);
      replacement.events.first['source_version'] = 'different-source';
    };
    final harness = AudioPlaybackHarness(
      transport: first,
      connectionFactory: () => replacement,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => MemoryPcmOutput(),
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.messages.any((event) => event['source_rejected'] == true));
    expect(harness.messages.where((event) => event['type'] == 'complete'), isEmpty);
    expect(harness.messages.where((event) => event['type'] == 'started').length, lessThanOrEqualTo(1));
  });

  test('duplicate route hints preserve a healthy paused transport without replacement', () async {
    final first = MemoryQuic();
    first.onRequest = (start, seekId) => first.deliverRange(startMs: start, endMs: 10000);
    final replacement = MemoryQuic();
    replacement.onRequest = (start, seekId) => replacement.deliverRange(startMs: start, endMs: 10000);
    final output = MemoryPcmOutput();
    var connections = 0;
    final harness = AudioPlaybackHarness(
      transport: first,
      connectionFactory: () {
        connections++;
        return replacement;
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: true,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.cachedAheadMilliseconds(0) >= 2000);
    harness.notifyNetworkChange(1);
    harness.notifyNetworkChange(1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(replacement.requestedPositions, isEmpty);
    expect(connections, 0);
    expect(harness.paused, isTrue);
    expect(output.samplesWritten, 0);
    expect(output.flushes, 0);
  });

  test('recovery budget and attempts cannot be renewed by trickled non-playable data', () {
    var now = Duration.zero;
    final episode = AudioRecoveryEpisode(now: () => now)..begin(100);
    expect(episode.reserveAttempt(), isTrue);
    now = const Duration(seconds: 4);
    episode.begin(101);
    episode.observe(acceptedThrough: 101, playableMilliseconds: 0);
    expect(episode.remaining, const Duration(seconds: 26));
    expect(episode.reserveAttempt(), isTrue);
    expect(episode.reserveAttempt(), isTrue);
    expect(episode.reserveAttempt(), isFalse);
    now = AudioRecoveryPolicy.budget;
    expect(episode.remaining, Duration.zero);
    expect(episode.active, isTrue);
  });

  test('a closed transport cannot interrupt an entirely retained final range', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) {
      transport.deliverRange(startMs: 0, endMs: 400, durationMs: 400, endOfTrack: true);
      transport.closed = true;
    };
    final output = MemoryPcmOutput();
    var replacements = 0;
    final harness = AudioPlaybackHarness(
      transport: transport,
      connectionFactory: () {
        replacements++;
        throw StateError('Network is unavailable.');
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: true,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.cachedAheadMilliseconds(0) == 400);
    harness.notifyNetworkChange(1);
    harness.resume();
    await waitUntil(() => harness.messages.any((event) => event['type'] == 'complete'));
    expect(replacements, 0);
    expect(output.samplesWritten, 19200 * 2);
    expect(output.flushes, 0);
  });

  test('recovery only ends after playable progress and a healthy interval', () {
    var now = Duration.zero;
    final episode = AudioRecoveryEpisode(now: () => now)..begin(100);
    episode.reserveAttempt();
    episode.observe(acceptedThrough: 100, playableMilliseconds: 8000);
    now = const Duration(seconds: 3);
    expect(episode.active, isTrue);
    episode.observe(acceptedThrough: 200, playableMilliseconds: 8000);
    now = const Duration(seconds: 4);
    episode.interrupted();
    episode.observe(acceptedThrough: 200, playableMilliseconds: 8000);
    now = const Duration(seconds: 5);
    episode.observe(acceptedThrough: 300, playableMilliseconds: 8000);
    expect(episode.active, isTrue);
    now = const Duration(seconds: 6);
    episode.observe(acceptedThrough: 400, playableMilliseconds: 8000);
    expect(episode.active, isFalse);
  });

  test('cached seek remains usable when retired transport rejects telemetry', () async {
    final transport = _RetiredTelemetryQuic();
    transport.onRequest = (start, seekId) =>
        transport.deliverRange(startMs: 0, endMs: 1000, durationMs: 1000, endOfTrack: true);
    final output = MemoryPcmOutput();
    var replacements = 0;
    final harness = AudioPlaybackHarness(
      transport: transport,
      connectionFactory: () {
        replacements++;
        throw StateError('No route.');
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      initialPaused: true,
    );
    addTearDown(harness.close);
    harness.start();
    await waitUntil(() => harness.cachedAheadMilliseconds(0) == 1000);
    transport.closed = true;
    expect(await harness.seek(const Duration(milliseconds: 250)), isTrue);
    expect(harness.paused, isTrue);
    harness.notifyNetworkChange(1);
    harness.resume();
    await waitUntil(() => harness.messages.any((event) => event['type'] == 'complete'));
    expect(replacements, 0);
    expect(output.samplesWritten, 750 * 48 * 2);
  });

  test('PCM append can commit an aligned prefix without consuming the tail', () {
    final buffer = PcmRingBuffer(5, bitsPerSample: 32);
    final samples = Int32List.fromList(<int>[1, 2, 3, 4, 5, 6]);
    expect(buffer.write(samples, 0, 4), 4);
    expect(buffer.read(4), <int>[1, 2, 3, 4]);
    expect(buffer.write(samples, 4, 2), 2);
    expect(buffer.read(2), <int>[5, 6]);
  });
}
