import 'dart:math' as math;

import 'package:phonolite_app/application/app/app_controller.dart';

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

String playbackFormatTime(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    final hh = hours.toString();

    return '$hh:$mm:$ss';
  }

  return '$minutes:$ss';
}

String playbackShuffleLabel(ShuffleMode mode) {
  switch (mode) {
    case ShuffleMode.off:
      return 'Off';
    case ShuffleMode.all:
      return 'Whole Library';
    case ShuffleMode.artist:
      return 'Current Artist';
    case ShuffleMode.album:
      return 'Current Album';
    case ShuffleMode.currentPlaylist:
      return 'Current Playlist';
    case ShuffleMode.custom:
      return 'Custom';
    case ShuffleMode.liked:
      return 'Liked';
  }
}

String? playbackBitrateLabel(PlaybackState state) {
  if (state.isLocalPlayback || state.streamMode == StreamMode.original) {
    return null;
  }

  final bitrate = state.bitrateKbps;

  if (bitrate == null || bitrate.isNaN || bitrate.isInfinite || bitrate <= 0) {
    return null;
  }

  final rounded = bitrate.round();

  return '$rounded KBPS';
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

String? playbackQueueSourceLabel(PlaybackState state) {
  switch (state.queueSource) {
    case PlaybackQueueSource.none:
      return null;
    case PlaybackQueueSource.liked:
      return 'LIKED TRACKS';
    case PlaybackQueueSource.playlist:
      return null;
    case PlaybackQueueSource.offline:
      switch (state.localPlaybackSource) {
        case LocalPlaybackSource.none:
          return state.isLocalPlayback ? 'SOURCE: LOCAL' : null;
        case LocalPlaybackSource.library:
          return null;
        case LocalPlaybackSource.liked:
          return 'LIKED TRACKS';
        case LocalPlaybackSource.playlist:
          return null;
      }
  }
}
