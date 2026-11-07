import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// Bounded PCM storage indexed by absolute presentation frames per channel.
/// Discarding played frames never renumbers the remaining source timeline.
class AlignedPcmBuffer {
  final int channels;
  final int capacityFrames;
  final ListQueue<Int32List> _chunks = ListQueue();
  int _startFrame;
  int _endFrame;
  int _headOffset = 0;

  AlignedPcmBuffer({required this.channels, required this.capacityFrames, required int startFrame})
    : assert(channels > 0),
      assert(capacityFrames > 0),
      assert(startFrame >= 0),
      _startFrame = startFrame,
      _endFrame = startFrame;

  int get endFrame => _endFrame;

  int get freeFrames => capacityFrames - (_endFrame - _startFrame);

  int availableAt(int frame) => frame < _startFrame || frame > _endFrame ? 0 : _endFrame - frame;

  void append(Int32List samples) {
    if (samples.length % channels != 0 || samples.length ~/ channels > freeFrames) {
      throw StateError('Aligned PCM append exceeds capacity or ends inside a frame.');
    }

    if (samples.isEmpty) {
      return;
    }
    _chunks.add(samples);
    _endFrame += samples.length ~/ channels;
  }

  void discardBefore(int frame) {
    var samples = (math.min(frame, _endFrame) - _startFrame).clamp(0, capacityFrames) * channels;

    while (samples > 0 && _chunks.isNotEmpty) {
      final count = math.min(samples, _chunks.first.length - _headOffset);
      _headOffset += count;
      _startFrame += count ~/ channels;
      samples -= count;
      if (_headOffset == _chunks.first.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
  }

  Int32List? readAt(int frame, int frames) {
    if (frames < 0) {
      throw ArgumentError.value(frames, 'frames');
    }
    if (availableAt(frame) < frames) {
      return null;
    }
    discardBefore(frame);
    final result = Int32List(frames * channels);
    var offset = 0;

    for (final chunk in _chunks) {
      final start = offset == 0 ? _headOffset : 0;
      final count = math.min(result.length - offset, chunk.length - start);
      result.setRange(offset, offset + count, chunk, start);
      offset += count;
      if (offset == result.length) {
        break;
      }
    }

    discardBefore(frame + frames);

    return result;
  }
}
