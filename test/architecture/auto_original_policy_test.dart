import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/audio_original_descriptor.dart';
import 'package:phonolite_app/data/rules/audio/auto_original_policy.dart';
import 'package:phonolite_app/data/structures/audio/aligned_pcm_buffer.dart';
import 'package:phonolite_app/data/structures/audio/audio_rendition_mixer.dart';

void main() {
  test('Original descriptor rejects absent identity, size and duration', () {
    for (final value in [
      null,
      {},
      {'source_version': 'v', 'total_length': 0, 'duration_ms': 1000},
    ]) {
      expect(AudioOriginalDescriptor.tryParse(value), isNull);
    }
    final descriptor = AudioOriginalDescriptor.tryParse({
      'source_version': 'v',
      'total_length': 12000,
      'duration_ms': 1000,
    })!;
    expect(descriptor.averageBitrateBps, 96000);
    expect(descriptor.sourceMetadata, {'source_version': 'v', 'total_length': 12000});
  });

  test('moderate sustained headroom can enter OG and reserve absorbs slower intervals', () {
    final policy = AutoOriginalPolicy();
    expect(policy.mayPrepare(now: Duration.zero, fallbackReserveMs: 8000, active: true), isFalse);
    expect(policy.mayPrepare(now: const Duration(seconds: 2), fallbackReserveMs: 7000, active: true), isTrue);
    expect(
      policy.select(
        now: const Duration(seconds: 4),
        reserveMs: 4000,
        deliveryRatio: 1.2,
        failed: false,
        complete: false,
      ),
      isTrue,
    );
    expect(
      policy.select(
        now: const Duration(seconds: 5),
        reserveMs: 6000,
        deliveryRatio: 0.8,
        failed: false,
        complete: false,
      ),
      isTrue,
    );
    expect(
      policy.select(
        now: const Duration(seconds: 6),
        reserveMs: 1999,
        deliveryRatio: 0.8,
        failed: false,
        complete: false,
      ),
      isFalse,
    );
    expect(
      policy.select(now: const Duration(seconds: 7), reserveMs: 8000, deliveryRatio: 4, failed: false, complete: false),
      isFalse,
    );
    expect(
      policy.select(
        now: const Duration(seconds: 36),
        reserveMs: 8000,
        deliveryRatio: 1.2,
        failed: false,
        complete: false,
      ),
      isTrue,
    );
  });

  test('a weak fallback reserve and paused preparation do not qualify', () {
    final policy = AutoOriginalPolicy();
    policy.mayPrepare(now: Duration.zero, fallbackReserveMs: 8000, active: true);
    expect(policy.mayPrepare(now: const Duration(seconds: 2), fallbackReserveMs: 2000, active: true), isFalse);
    expect(policy.mayPrepare(now: const Duration(seconds: 3), fallbackReserveMs: 8000, active: false), isFalse);
    expect(
      policy.select(
        now: const Duration(seconds: 4),
        reserveMs: 8000,
        deliveryRatio: 0.9,
        failed: false,
        complete: false,
      ),
      isFalse,
    );
  });

  test('a completely buffered tail stays OG while its reserve drains normally', () {
    final policy = AutoOriginalPolicy();
    policy.select(now: Duration.zero, reserveMs: 5000, deliveryRatio: 1.2, failed: false, complete: false);
    expect(
      policy.select(now: const Duration(seconds: 4), reserveMs: 300, deliveryRatio: 1.2, failed: false, complete: true),
      isTrue,
    );
    expect(
      policy.select(now: const Duration(seconds: 4), reserveMs: 300, deliveryRatio: 1.2, failed: true, complete: true),
      isFalse,
    );
  });

  test('aligned PCM joins chunks without replay, gaps or unbounded storage', () {
    final buffer = AlignedPcmBuffer(channels: 2, capacityFrames: 5, startFrame: 100);
    buffer.append(Int32List.fromList([10, 11, 20, 21]));
    buffer.append(Int32List.fromList([30, 31, 40, 41, 50, 51]));
    expect(buffer.freeFrames, 0);
    expect(buffer.readAt(101, 3), [20, 21, 30, 31, 40, 41]);
    expect(buffer.availableAt(101), 0);
    expect(buffer.freeFrames, 4);
    expect(buffer.readAt(104, 2), isNull);
    expect(buffer.readAt(104, 1), [50, 51]);
    expect(() => buffer.append(Int32List(3)), throwsStateError);
    expect(() => buffer.append(Int32List(12)), throwsStateError);
  });

  test('switching both directions blends aligned frames and preserves PCM32 precision', () {
    final mixer = AudioRenditionMixer(channels: 1, transitionFrames: 4);
    final opus = Int16List.fromList([100, 100, 100, 100]);
    final original = Int32List.fromList(List.filled(4, (100 << 16) + 4000));
    expect(mixer.mix(opus, null, useOriginal: false), List.filled(4, 100 << 16));
    expect(mixer.mix(opus, original, useOriginal: true), [6554600, 6555600, 6556600, 6557600]);
    expect(mixer.mix(opus, original, useOriginal: true), original);
    expect(mixer.mix(opus, original, useOriginal: false), [6556600, 6555600, 6554600, 6553600]);
  });
}
