import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/structures/audio/encoded_audio_cache.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_app/infrastructure/audio/protocol/raw_opus_stream_reader.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

import '../support/streaming_test_helpers.dart';

Uint8List exactHeader({required int frames, int preSkip = 312, int durationMs = 400}) {
  final legacy = rawHeader(durationMs: durationMs, preSkip: preSkip);
  final header = Uint8List(legacy.length + 8)..setAll(0, legacy);
  header[9] = 1;
  final bytes = ByteData.sublistView(header);
  bytes.setUint16(10, header.length, Endian.little);
  bytes.setUint64(legacy.length, frames, Endian.little);
  return header;
}

void deliverExactRange(
  MemoryQuic transport, {
  required int startMs,
  required int endMs,
  required int frames,
  int durationMs = 400,
  int preSkip = 312,
  int? seekId,
  int value = 1,
  int? packetCount,
  bool endOfTrack = true,
}) {
  transport.deliverRange(
    startMs: startMs,
    endMs: endMs,
    durationMs: durationMs,
    preSkip: preSkip,
    seekId: seekId,
    value: value,
    packetCount: packetCount ?? ((frames + preSkip + 959) ~/ 960),
    endOfTrack: endOfTrack,
  );
  final oldHeader = transport.chunks.removeFirst();
  final prefixLength = seekId == null ? 0 : 6;
  final first = BytesBuilder()
    ..add(oldHeader.sublist(0, prefixLength))
    ..add(exactHeader(frames: frames, preSkip: preSkip, durationMs: durationMs));
  transport.chunks.addFirst(first.takeBytes());
}

EncodedAudioSegment segmentFor(int frames, {int preSkip = 4152, int nominalEndMs = 445}) => EncodedAudioSegment(
  header: RawOpusHeader.parse(exactHeader(frames: frames, preSkip: preSkip)),
  startMs: 0,
  rangeEndMs: nominalEndMs,
  endOfTrack: true,
  sourceVersion: 'source',
);

void main() {
  test('R01 flags append exact per-channel frames after all metadata', () {
    final header = RawOpusHeader.parse(exactHeader(frames: 19207, preSkip: 4152));
    expect(header.playableFrames, 19207);
    expect(header.preSkip, 4152);
    expect(header.sampleRate, 48000);
    expect(header.channels, 2);
    expect(header.frameMs, 20);
    expect(header.durationMs, 400);
  });

  test('legacy headers keep unknown exact length and preserve codec pre-skip', () {
    final header = RawOpusHeader.parse(rawHeader(durationMs: 400, preSkip: 4152));
    expect(header.playableFrames, isNull);
    expect(header.preSkip, 4152);
  });

  test('missing, extra and overlapping exact extensions are rejected', () {
    final missing = rawHeader()..[9] = 1;
    expect(() => RawOpusHeader.parse(missing), throwsA(isA<OpusException>()));
    final extra = Uint8List.fromList(<int>[...exactHeader(frames: 1), 0]);
    ByteData.sublistView(extra).setUint16(10, extra.length, Endian.little);
    expect(() => RawOpusHeader.parse(extra), throwsA(isA<OpusException>()));
    final overlap = exactHeader(frames: 1);
    ByteData.sublistView(overlap).setUint16(28, 20, Endian.little);
    expect(() => RawOpusHeader.parse(overlap), throwsA(isA<OpusException>()));
    final truncated = exactHeader(frames: 1);
    expect(
      () => RawOpusHeader.parse(Uint8List.sublistView(truncated, 0, truncated.length - 1)),
      throwsA(isA<OpusException>()),
    );
  });

  test('exact lengths outside safe nonnegative frame range are rejected', () {
    for (final count in <int>[-1, 0x20000000000000]) {
      expect(() => RawOpusHeader.parse(exactHeader(frames: count)), throwsA(isA<OpusException>()));
    }
  });

  test('incremental framing retains exact extension across byte-sized reads', () {
    final reader = RawOpusStreamReader();
    final events = <RawOpusEvent>[];
    final bytes = <int>[...exactHeader(frames: 19207, preSkip: 4152), 1, 0, 7, 0, 0];
    for (final byte in bytes) {
      events.addAll(reader.add(Uint8List.fromList(<int>[byte])));
    }
    expect(events.length, 3);
    expect((events[0] as RawOpusStreamHeader).header.playableFrames, 19207);
    expect((events[1] as RawOpusPacket).bytes, <int>[7]);
    expect(events[2], isA<RawOpusEnd>());
  });

  test('cache completion requires EOS and sufficient frames after full priming', () {
    final cache = EncodedAudioCache();
    final segment = segmentFor(19207);
    cache.addSegment(segment);
    for (var n = 0; n < 24; n++) {
      cache.append(segment, Uint8List.fromList(<int>[1]));
    }
    segment.complete = true;
    expect(segment.hasAllFrames, isFalse);
    cache.append(segment, Uint8List.fromList(<int>[1]));
    segment.complete = false;
    expect(segment.hasAllFrames, isFalse);
    segment.complete = true;
    expect(segment.hasAllFrames, isTrue);
    expect(segment.playableFrames, 19207);
    expect(segment.availableEndMs, 445, reason: 'nominal duration may include known discarded padding');
  });

  test('zero-frame discarded tails complete with header and EOS alone', () {
    final segment = segmentFor(0, preSkip: 0);
    expect(segment.hasAllFrames, isFalse);
    segment.complete = true;
    expect(segment.hasAllFrames, isTrue);
    expect(segment.packets, isEmpty);
  });

  test('production pipeline preserves non-ms tail and removes 80ms primer once', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => deliverExactRange(
      transport,
      startMs: start,
      endMs: 445,
      frames: 19207,
      preSkip: 4152,
      durationMs: 445,
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
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.messages.any((event) => event['type'] == 'complete'));
    expect(output.samplesWritten, 19207 * 2);
    expect(opens, 1);
    expect(output.flushes, 0);
    expect(transport.requestedPositions, <int>[0]);
  });

  test('production pipeline completes zero-frame final tail without writing silence', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => deliverExactRange(
      transport,
      startMs: start,
      endMs: 445,
      frames: 0,
      preSkip: 0,
      durationMs: 445,
      seekId: seekId,
    );
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
      startOffset: const Duration(milliseconds: 420),
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.messages.any((event) => event['type'] == 'complete'));
    expect(output.samplesWritten, 0);
    expect(output.writes, 0);
  });

  test('independent ranges join without duplicate encoder priming or lost tail', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => deliverExactRange(
      transport,
      startMs: start,
      endMs: start == 0 ? 400 : 800,
      frames: start == 0 ? 19200 : 19207,
      preSkip: start == 0 ? 312 : 4152,
      durationMs: 800,
      seekId: seekId,
      value: start == 0 ? 1 : 2,
      endOfTrack: start != 0,
    );
    final output = MemoryPcmOutput();
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => output,
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.messages.any((event) => event['type'] == 'complete'));
    expect(output.samplesWritten, (19200 + 19207) * 2);
    expect(output.values, containsAll(<int>[1, 2]));
    expect(transport.requestedPositions, <int>[0, 400]);
    expect(output.flushes, 0);
  });

  test('local cached seek retains exact final frames with large pre-skip', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => deliverExactRange(
      transport,
      startMs: start,
      endMs: 445,
      frames: 19207,
      preSkip: 4152,
      durationMs: 445,
      seekId: seekId,
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
    await waitUntil(() => session.cachedAheadMilliseconds(0) == 445);
    expect(await session.seek(const Duration(milliseconds: 105)), isTrue);
    session.resume();
    await waitUntil(() => session.messages.any((event) => event['type'] == 'complete'));
    expect(output.samplesWritten, (19207 - 105 * 48) * 2);
    expect(transport.requestedPositions, <int>[0]);
    expect(output.flushes, 1);
  });

  test('short completed range is a failure rather than successful EOF', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) => deliverExactRange(
      transport,
      startMs: start,
      endMs: 445,
      frames: 19207,
      preSkip: 4152,
      packetCount: 24,
      durationMs: 445,
      seekId: seekId,
    );
    final session = AudioPlaybackHarness(
      transport: transport,
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => MemoryPcmOutput(),
    );
    addTearDown(session.close);
    session.start();
    await waitUntil(() => session.messages.any((event) => event['type'] == 'state' && event['active'] == false));
    expect(session.messages.any((event) => event['type'] == 'complete'), isFalse);
  });
}
