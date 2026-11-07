import 'dart:collection';

import 'package:phonolite_app/data/models/audio/audio_stream_quality.dart';

/// Tracks rendition boundaries in accepted interleaved PCM samples. Playback
/// consumption, rather than decoding or prefetch, selects the visible quality.
class AudioQualityTimeline {
  final ListQueue<({int start, AudioStreamQuality? quality})> _boundaries = ListQueue();
  int _acceptedSamples = 0;

  void reset() {
    _boundaries.clear();
    _acceptedSamples = 0;
  }

  void append(int samples, AudioStreamQuality? quality) {
    if (samples <= 0) {
      return;
    }

    if (_boundaries.isEmpty || _boundaries.last.quality != quality) {
      _boundaries.add((start: _acceptedSamples, quality: quality));
    }
    _acceptedSamples += samples;
  }

  AudioStreamQuality? qualityAt(int playedSamples) {
    while (_boundaries.length > 1 && _boundaries.elementAt(1).start <= playedSamples) {
      _boundaries.removeFirst();
    }

    return _boundaries.firstOrNull?.quality;
  }
}
