import 'package:phonolite_app/data/models/library/track.dart';

const Object _unset = Object();

enum ShuffleMode { off, all, artist, album, custom, liked, currentPlaylist }

enum ActionScope { local, server }

enum PlaybackRepeatMode { off, one }

/// Original preserves source-file bytes over QUIC; the other qualities use Opus.
enum StreamMode { auto, high, medium, low, original }

enum PlaybackQueueSource { none, liked, playlist, offline }

enum LocalPlaybackSource { none, library, liked, playlist }

class PlaybackState {
  final Track? track;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final double bufferRatio;
  final double volume;
  final ShuffleMode localShuffleMode;
  final ShuffleMode serverShuffleMode;
  final ActionScope shuffleScope;
  final PlaybackRepeatMode repeatMode;
  final StreamMode streamMode;
  final double? bitrateKbps;
  final bool streamConnected;
  final int? streamRttMs;
  final PlaybackQueueSource queueSource;
  final String? queueSourcePlaylistId;
  final LocalPlaybackSource localPlaybackSource;
  final bool isLocalPlayback;

  PlaybackState({
    required this.track,
    required this.isPlaying,
    required this.isLoading,
    required this.position,
    required this.duration,
    required this.bufferRatio,
    required this.volume,
    required ShuffleMode shuffleMode,
    required this.shuffleScope,
    required this.repeatMode,
    required this.streamMode,
    required this.bitrateKbps,
    required this.streamConnected,
    required this.streamRttMs,
    required this.queueSource,
    required this.queueSourcePlaylistId,
    required this.localPlaybackSource,
    required this.isLocalPlayback,
    ShuffleMode? localShuffleMode,
    ShuffleMode? serverShuffleMode,
  }) : localShuffleMode = shuffleScope == ActionScope.local ? shuffleMode : localShuffleMode ?? ShuffleMode.off,
       serverShuffleMode = shuffleScope == ActionScope.server ? shuffleMode : serverShuffleMode ?? ShuffleMode.off;

  ShuffleMode get shuffleMode => shuffleModeFor(shuffleScope);

  bool get hasPlaylistSource {
    if (queueSourcePlaylistId?.trim().isNotEmpty != true) {
      return false;
    }

    return switch (queueSource) {
      PlaybackQueueSource.playlist => true,
      PlaybackQueueSource.offline => localPlaybackSource == LocalPlaybackSource.playlist,
      PlaybackQueueSource.none || PlaybackQueueSource.liked => false,
    };
  }

  ShuffleMode shuffleModeFor(ActionScope scope) => switch (scope) {
    ActionScope.local => localShuffleMode,
    ActionScope.server => serverShuffleMode,
  };

  /// Nullable fields keep their values when omitted and clear on explicit null.
  PlaybackState copyWith({
    Object? track = _unset,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    double? bufferRatio,
    double? volume,
    ShuffleMode? shuffleMode,
    ActionScope? shuffleScope,
    PlaybackRepeatMode? repeatMode,
    StreamMode? streamMode,
    Object? bitrateKbps = _unset,
    bool? streamConnected,
    Object? streamRttMs = _unset,
    PlaybackQueueSource? queueSource,
    Object? queueSourcePlaylistId = _unset,
    LocalPlaybackSource? localPlaybackSource,
    bool? isLocalPlayback,
  }) {
    final nextShuffleScope = shuffleScope ?? this.shuffleScope;

    return PlaybackState(
      track: identical(track, _unset) ? this.track : track as Track?,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferRatio: bufferRatio ?? this.bufferRatio,
      volume: volume ?? this.volume,
      shuffleMode: shuffleMode ?? shuffleModeFor(nextShuffleScope),
      shuffleScope: nextShuffleScope,
      localShuffleMode: localShuffleMode,
      serverShuffleMode: serverShuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
      streamMode: streamMode ?? this.streamMode,
      bitrateKbps: identical(bitrateKbps, _unset) ? this.bitrateKbps : (bitrateKbps as num?)?.toDouble(),
      streamConnected: streamConnected ?? this.streamConnected,
      streamRttMs: identical(streamRttMs, _unset) ? this.streamRttMs : streamRttMs as int?,
      queueSource: queueSource ?? this.queueSource,
      queueSourcePlaylistId: identical(queueSourcePlaylistId, _unset)
          ? this.queueSourcePlaylistId
          : queueSourcePlaylistId as String?,
      localPlaybackSource: localPlaybackSource ?? this.localPlaybackSource,
      isLocalPlayback: isLocalPlayback ?? this.isLocalPlayback,
    );
  }
}
