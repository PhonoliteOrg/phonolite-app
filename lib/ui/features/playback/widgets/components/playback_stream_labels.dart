import 'dart:math' as math;

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/audio/audio_stream_quality.dart';

String playbackStreamLabel(StreamMode mode) {
  switch (mode) {
    case StreamMode.auto:
      return 'AUTO';
    case StreamMode.high:
      return 'HQ';
    case StreamMode.medium:
      return 'MQ';
    case StreamMode.low:
      return 'LQ';
    case StreamMode.original:
      return 'OG';
  }
}

String? playbackActiveQualityLabel(PlaybackState state) {
  if (state.track == null || state.isLocalPlayback || state.streamMode != StreamMode.auto || !state.streamConnected) {
    return null;
  }

  return switch (state.streamQuality) {
    AudioStreamQuality.original => 'OG',
    AudioStreamQuality.high => 'HQ',
    AudioStreamQuality.medium => 'MQ',
    AudioStreamQuality.low => 'LQ',
    null => null,
  };
}

String? playbackRttLabel(PlaybackState state) {
  final rtt = state.streamRttMs;

  if (state.isLocalPlayback || rtt == null) {
    return null;
  }

  return '${rtt}ms';
}

String? playbackBufferAheadLabel(PlaybackState state) {
  if (state.track == null || state.isLocalPlayback) {
    return null;
  }

  final durationMs = state.duration.inMilliseconds;

  if (durationMs <= 0) {
    return null;
  }

  final bufferedEndMs = (state.bufferRatio.clamp(0.0, 1.0) * durationMs).round();
  final aheadMs = math.max(0, bufferedEndMs - state.position.inMilliseconds);
  final aheadSeconds = aheadMs / 1000.0;
  final label = aheadSeconds < 10 ? aheadSeconds.toStringAsFixed(1) : aheadSeconds.round().toString();

  return 'BUF ${label}s';
}
