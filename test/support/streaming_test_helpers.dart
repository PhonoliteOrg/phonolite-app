import 'dart:collection';
import 'dart:typed_data';

import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_opus/phonolite_opus.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

Uint8List rawHeader({int durationMs = 60000, int preSkip = 312}) {
  final bytes = Uint8List(45);
  bytes.setRange(0, 8, 'OPUSR01\u0000'.codeUnits);
  bytes[8] = 1;
  final view = ByteData.sublistView(bytes);
  view.setUint16(10, bytes.length, Endian.little);
  view.setUint32(12, 48000, Endian.little);
  bytes[16] = 2;
  bytes[17] = 20;
  view.setUint32(18, 160000, Endian.little);
  view.setUint32(22, durationMs, Endian.little);
  view.setUint16(26, preSkip, Endian.little);
  view.setUint16(28, 5, Endian.little);
  bytes.setRange(40, 45, 'track'.codeUnits);
  return bytes;
}

class MemoryQuic implements QuicClient {
  final chunks = Queue<Uint8List>();
  final events = Queue<Map<String, Object?>>();
  final requestedPositions = <int>[];
  final bufferReports = <(int, int?)>[];
  void Function(int startMs, int? seekId)? onRequest;
  int _generation = 0;
  int suspensions = 0;
  bool closed = false;

  @override
  int get requestId => _generation;

  @override
  int openTrack({
    required String trackId,
    String? mode,
    String? quality,
    int frameMs = 20,
    List<String> queue = const [],
    int startMs = 0,
  }) {
    _generation++;
    chunks.clear();
    events.clear();
    requestedPositions.add(startMs);
    onRequest?.call(startMs, null);
    return _generation;
  }

  @override
  int seek({required String trackId, required int positionMs, required int seekId}) {
    _generation++;
    chunks.clear();
    events.clear();
    requestedPositions.add(positionMs);
    onRequest?.call(positionMs, seekId);
    return _generation;
  }

  void deliverRange({
    required int startMs,
    required int endMs,
    int durationMs = 60000,
    int value = 1,
    int? seekId,
    bool complete = true,
    bool endOfTrack = false,
    int preSkip = 312,
    int? packetCount,
  }) {
    events.add({
      'type': 'stream',
      'request_id': _generation,
      'position_ms': startMs,
      'range_end_ms': endMs,
      'end_of_track': endOfTrack,
      'source_version': 'source-v1',
    });
    final first = BytesBuilder();
    if (seekId != null) {
      final marker = Uint8List(6)
        ..[0] = 255
        ..[1] = 255;
      ByteData.sublistView(marker).setUint32(2, seekId, Endian.little);
      first.add(marker);
    }
    first.add(rawHeader(durationMs: durationMs, preSkip: preSkip));
    chunks.add(first.takeBytes());
    final frames = packetCount ?? (((endMs - startMs) * 48 + preSkip) / 960).ceil();
    for (var i = 0; i < frames; i += 10) {
      final frameBytes = BytesBuilder();
      for (var j = i; j < frames && j < i + 10; j++) {
        frameBytes.add([1, 0, value]);
      }
      chunks.add(frameBytes.takeBytes());
    }
    if (complete) chunks.add(Uint8List.fromList([0, 0]));
  }

  @override
  int read(Uint8List buffer) {
    if (chunks.isEmpty) return closed ? 0 : -5;
    final chunk = chunks.removeFirst();
    final count = chunk.length < buffer.length ? chunk.length : buffer.length;
    buffer.setRange(0, count, chunk);
    if (count < chunk.length) {
      chunks.addFirst(Uint8List.sublistView(chunk, count));
    }
    return count;
  }

  @override
  Map<String, Object?>? pollEvent() => events.isEmpty ? null : events.removeFirst();
  @override
  void suspendAudio() {
    suspensions++;
    chunks.clear();
    events.clear();
  }

  @override
  void sendBufferStats({required int bufferMs, int? targetMs, bool force = false}) {
    bufferReports.add((bufferMs, targetMs));
  }

  @override
  void sendPlayback({required String trackId, required int positionMs, required bool playing}) {}
  @override
  String? pollStats() => null;
  @override
  int? pollRttMs() => 1;
  @override
  String? lastError() => null;
  @override
  void close() {
    closed = true;
    chunks.clear();
    events.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryOpusDecoder implements OpusDecoder {
  MemoryOpusDecoder(this.sampleRate, this.channels);
  @override
  final int sampleRate;
  @override
  final int channels;
  @override
  int get maxFrameSize => 5760;
  bool disposed = false;
  @override
  Int16List decode(Uint8List packet, {int? frameSize}) {
    if (disposed) throw StateError('Disposed decoder used');
    return Int16List((frameSize ?? 960) * channels)..fillRange(0, (frameSize ?? 960) * channels, packet.first);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class MemoryPcmOutput implements AudioPcmOutput, AudioPcm32Output {
  Future<bool> Function()? idleCheck;
  Future<void> Function()? flushCheck;
  bool paused = false;
  bool disposed = false;
  bool blockWrites = false;
  int epoch = 0;
  int flushes = 0;
  int writes = 0;
  int samplesWritten = 0;
  int _done = 0;
  final values = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> write(Int16List samples) => _writeSamples(samples);

  @override
  Future<void> writePcm32(Int32List samples) => _writeSamples(samples);

  Future<void> _writeSamples(List<int> samples) async {
    final generation = epoch;
    while (blockWrites && generation == epoch && !disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    if (generation != epoch || disposed) return;
    writes++;
    samplesWritten += samples.length;
    values.add(samples.first);
    if (!paused) _done += samples.length;
  }

  @override
  Future<void> flush() async {
    epoch++;
    flushes++;
    _done = 0;
    await flushCheck?.call();
  }

  @override
  Future<void> dispose() async {
    epoch++;
    disposed = true;
  }

  @override
  void setVolume(double value) {}
  @override
  void pause() {
    paused = true;
  }

  @override
  void resume() {
    paused = false;
  }

  @override
  Future<int> collectDoneSamples() async {
    final done = _done;
    _done = 0;
    return done;
  }

  @override
  Future<bool> isIdle() async => await idleCheck?.call() ?? true;
}

Future<void> waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
