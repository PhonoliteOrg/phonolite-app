import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:phonolite_opus/phonolite_opus.dart';

/// Retained compressed audio, separate from the short, consumable PCM queue.
/// A segment is one independently encoded range with its own decoder preskip.
class EncodedAudioSegment {
  final RawOpusHeader header;
  final int startMs;
  final int rangeEndMs;
  final bool endOfTrack;
  final String sourceVersion;
  final List<Uint8List> _packets = [];
  late final List<Uint8List> _packetView = UnmodifiableListView(_packets);
  bool complete = false;

  /// Retained bytes charged to the cache, including object/storage overhead.
  int _bytes = 0;

  EncodedAudioSegment({
    required this.header,
    required this.startMs,
    required this.rangeEndMs,
    required this.endOfTrack,
    required this.sourceVersion,
  });

  /// Live read-only packet ordering; only the cache may add or release packets.
  List<Uint8List> get packets => _packetView;

  int get bytes => _bytes;

  int get frameSamples => header.sampleRate * header.frameMs ~/ 1000;

  int get availableEndMs => math.min(
    rangeEndMs,
    startMs + math.max(0, packets.length * frameSamples - header.preSkip) * 1000 ~/ header.sampleRate,
  );

  bool covers(int positionMs) => positionMs >= startMs && positionMs < availableEndMs;

  EncodedAudioCursor cursorAt(int positionMs, {int prerollMs = 100}) {
    final targetSamples = (positionMs - startMs) * header.sampleRate ~/ 1000 + header.preSkip;
    final prerollFrames = (prerollMs + header.frameMs - 1) ~/ header.frameMs;
    final index = math.max(0, targetSamples ~/ frameSamples - prerollFrames);

    return EncodedAudioCursor(
      segment: this,
      packetIndex: index,
      skipSamplesPerChannel: targetSamples - index * frameSamples,
      positionMs: positionMs,
    );
  }
}

class EncodedAudioCursor {
  final EncodedAudioSegment segment;
  int packetIndex;
  int skipSamplesPerChannel;
  int positionMs;

  EncodedAudioCursor({
    required this.segment,
    required this.packetIndex,
    required this.skipSamplesPerChannel,
    required this.positionMs,
  });
}

/// Session-scoped: track, credentials, source version and rendition cannot leak
/// between playback sessions. Pinned producer/decoder ranges count in the budget.
class EncodedAudioCache {
  // Small Opus silence packets still retain a typed-data object and list slot.
  // Charging these prevents a payload-only budget from retaining millions of
  // allocations. Segment charges include the header, metadata and packet list.
  static const int packetOverheadBytes = 64;
  static const int segmentOverheadBytes = 256;

  final int maxBytes;
  final int maxSegments;
  final List<EncodedAudioSegment> _segments = [];
  int _bytes = 0;
  String? _sourceVersion;

  EncodedAudioCache({this.maxBytes = 16 * 1024 * 1024, this.maxSegments = 64})
    : assert(maxBytes >= 0),
      assert(maxSegments > 0);

  int get bytes => _bytes;

  int get segmentCount => _segments.length;

  bool addSegment(EncodedAudioSegment segment, {EncodedAudioSegment? pinned}) {
    if (_segments.contains(segment)) {
      return true;
    }

    if (_sourceVersion != null && _sourceVersion != segment.sourceVersion) {
      clear();
    }

    if (!_reserve(segmentOverheadBytes, additionalSegments: 1, incoming: segment, pinned: pinned)) {
      return false;
    }

    _sourceVersion = segment.sourceVersion;
    segment._bytes = segmentOverheadBytes;
    _segments.add(segment);
    _bytes += segmentOverheadBytes;

    return true;
  }

  bool append(EncodedAudioSegment segment, Uint8List packet, {EncodedAudioSegment? pinned}) {
    if (!_segments.contains(segment)) {
      return false;
    }

    final charge = packet.length + packetOverheadBytes;

    if (!_reserve(charge, incoming: segment, pinned: pinned)) {
      return false;
    }

    segment._packets.add(packet);
    segment._bytes += charge;
    _bytes += charge;

    return true;
  }

  EncodedAudioCursor? seek(int positionMs) {
    // Prefer the newest matching range; older ranges may overlap a later seek.
    for (var i = _segments.length - 1; i >= 0; i--) {
      final segment = _segments[i];

      if (!segment.covers(positionMs)) {
        continue;
      }

      _segments.removeAt(i);
      _segments.add(segment);

      return segment.cursorAt(positionMs);
    }

    return null;
  }

  int bufferedAheadMs(int positionMs) {
    var endMs = positionMs;
    bool advanced;

    do {
      advanced = false;

      for (final segment in _segments) {
        if (segment.startMs <= endMs && segment.availableEndMs > endMs) {
          endMs = segment.availableEndMs;
          advanced = true;
        }
      }
    } while (advanced);

    return endMs - positionMs;
  }

  void clear() {
    for (final segment in _segments) {
      segment._packets.clear();
      segment._bytes = 0;
    }

    _segments.clear();
    _bytes = 0;
    _sourceVersion = null;
  }

  bool _reserve(
    int bytes, {
    int additionalSegments = 0,
    required EncodedAudioSegment incoming,
    EncodedAudioSegment? pinned,
  }) {
    if (bytes > maxBytes) {
      return false;
    }

    while (_bytes + bytes > maxBytes || _segments.length + additionalSegments > maxSegments) {
      final victim = _segments.cast<EncodedAudioSegment?>().firstWhere(
        (item) => !identical(item, incoming) && !identical(item, pinned),
        orElse: () => null,
      );
      if (victim == null) {
        return false;
      }

      _segments.remove(victim);
      _bytes -= victim.bytes;

      // Releasing packet storage also releases stale references after eviction.
      victim._packets.clear();
      victim._bytes = 0;
    }

    return true;
  }
}
