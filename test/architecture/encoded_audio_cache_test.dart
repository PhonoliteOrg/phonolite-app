import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/structures/audio/encoded_audio_cache.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

EncodedAudioSegment segment({int startMs = 0, int endMs = 30000, int preSkip = 312, String version = 'v1'}) =>
    EncodedAudioSegment(
      header: RawOpusHeader(
        sampleRate: 48000,
        channels: 2,
        frameMs: 20,
        bitrateBps: 160000,
        durationMs: 60000,
        preSkip: preSkip,
      ),
      startMs: startMs,
      rangeEndMs: endMs,
      endOfTrack: false,
      sourceVersion: version,
    );

void main() {
  test('packet views retain cache accounting and prevent outside structural mutation', () {
    final cache = EncodedAudioCache();
    final range = segment();
    final packets = range.packets;

    expect(cache.addSegment(range), isTrue);
    expect(cache.append(range, Uint8List(8)), isTrue);
    expect(packets, hasLength(1));
    expect(() => packets.add(Uint8List(50)), throwsUnsupportedError);
    expect(() => packets.clear(), throwsUnsupportedError);
    expect(range.bytes, EncodedAudioCache.segmentOverheadBytes + EncodedAudioCache.packetOverheadBytes + 8);
    expect(cache.bytes, range.bytes);

    cache.clear();

    expect(packets, isEmpty);
    expect(range.bytes, 0);
    expect(cache.bytes, 0);
  });

  test('partial ranges are seekable and decoder preroll lands on exact sample', () {
    final cache = EncodedAudioCache();
    final range = segment();
    cache.addSegment(range);
    for (var i = 0; i < 100; i++) {
      cache.append(range, Uint8List.fromList([i]));
    }
    expect(range.complete, isFalse);
    final cursor = cache.seek(1000)!;
    expect(cursor.packetIndex, 45);
    expect(cursor.skipSamplesPerChannel, 5112);
    expect(cursor.packetIndex * 960 + cursor.skipSamplesPerChannel - 312, 48000);
    expect(cache.seek(3000), isNull);
    expect(cache.bufferedAheadMs(1000), 993);
  });

  test('buffer horizon joins contiguous ranges and stops at holes', () {
    final cache = EncodedAudioCache();
    void add(int start, int end) {
      final range = segment(startMs: start, endMs: end, preSkip: 0);
      cache.addSegment(range);
      for (var i = start; i < end; i += 20) {
        cache.append(range, Uint8List.fromList([1]));
      }
    }

    add(0, 1000);
    add(1000, 2000);
    add(3000, 4000);
    expect(cache.bufferedAheadMs(500), 1500);
    expect(cache.bufferedAheadMs(2500), 0);
    expect(cache.seek(1000)!.segment.startMs, 1000);
  });

  test('LRU eviction counts pinned compressed data and releases old ranges', () {
    const rangeCharge = EncodedAudioCache.segmentOverheadBytes + EncodedAudioCache.packetOverheadBytes + 2;
    final cache = EncodedAudioCache(maxBytes: rangeCharge * 2);
    final old = segment();
    final pinned = segment(startMs: 1000);
    final incoming = segment(startMs: 2000);
    cache.addSegment(old);
    cache.append(old, Uint8List(2));
    cache.addSegment(pinned);
    cache.append(pinned, Uint8List(2));
    expect(cache.addSegment(incoming, pinned: pinned), isTrue);
    expect(cache.append(incoming, Uint8List(2), pinned: pinned), isTrue);
    expect(old.packets, isEmpty);
    expect(pinned.packets, hasLength(1));
    expect(cache.bytes, rangeCharge * 2);
    expect(cache.append(incoming, Uint8List(1), pinned: pinned), isFalse);
    expect(cache.bytes, rangeCharge * 2);
  });

  test('source changes invalidate retained packets', () {
    final cache = EncodedAudioCache();
    final old = segment();
    cache.addSegment(old);
    cache.append(old, Uint8List(2));
    cache.addSegment(segment(version: 'v2'));
    expect(cache.bytes, EncodedAudioCache.segmentOverheadBytes);
    expect(cache.segmentCount, 1);
    expect(old.packets, isEmpty);
    expect(cache.seek(0), isNull);
  });

  test('range padding does not claim audio beyond the declared boundary', () {
    final cache = EncodedAudioCache();
    final range = segment(endMs: 1000);
    cache.addSegment(range);
    for (var i = 0; i < 51; i++) {
      cache.append(range, Uint8List(1));
    }
    expect(range.availableEndMs, 1000);
    expect(cache.seek(999), isNotNull);
    expect(cache.seek(1000), isNull);
  });

  test('header-only cancelled ranges obey the segment cap and preserve pins', () {
    final cache = EncodedAudioCache(maxSegments: 2);
    final pinned = segment();
    expect(cache.addSegment(pinned), isTrue);
    for (var i = 0; i < 100; i++) {
      expect(cache.addSegment(segment(startMs: i * 1000), pinned: pinned), isTrue);
    }
    expect(cache.segmentCount, 2);
    expect(cache.bytes, 2 * EncodedAudioCache.segmentOverheadBytes);
    expect(pinned.bytes, EncodedAudioCache.segmentOverheadBytes);
    cache.clear();
    expect(cache.bytes, 0);
    expect(cache.segmentCount, 0);
    expect(pinned.bytes, 0);
  });

  test('new ranges cannot evict a pinned decoder to fit their headers', () {
    final cache = EncodedAudioCache(maxSegments: 1);
    final pinned = segment();
    final incoming = segment(startMs: 1000);
    expect(cache.addSegment(pinned), isTrue);
    expect(cache.addSegment(incoming, pinned: pinned), isFalse);
    expect(cache.segmentCount, 1);
    expect(cache.bytes, EncodedAudioCache.segmentOverheadBytes);
    expect(incoming.bytes, 0);
    expect(cache.append(incoming, Uint8List(3), pinned: pinned), isFalse);
    expect(cache.bytes, EncodedAudioCache.segmentOverheadBytes);
  });

  test('small silence packets include allocation overhead in the byte cap', () {
    const packetCharge = EncodedAudioCache.packetOverheadBytes + 3;
    const budget = EncodedAudioCache.segmentOverheadBytes + packetCharge * 3;
    final cache = EncodedAudioCache(maxBytes: budget);
    final range = segment();
    expect(cache.addSegment(range), isTrue);
    for (var i = 0; i < 3; i++) {
      expect(cache.append(range, Uint8List(3)), isTrue);
    }
    expect(cache.append(range, Uint8List(3)), isFalse);
    expect(range.packets, hasLength(3));
    expect(cache.bytes, budget);
    cache.clear();
    expect(cache.bytes, 0);
    expect(range.bytes, 0);
    expect(range.packets, isEmpty);
  });
}
