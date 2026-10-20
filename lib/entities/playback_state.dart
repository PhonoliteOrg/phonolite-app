import 'models.dart';

enum ShuffleMode { off, all, artist, album, custom, liked, currentPlaylist }

enum ActionScope { local, server }

enum RepeatMode { off, one }

enum StreamMode { auto, high, medium, low }

enum PlaybackQueueSource { none, liked, playlist, offline }

enum LocalPlaybackSource { none, library, liked, playlist }

const Object _unset = Object();

class PlaybackState {
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
    ShuffleMode? localShuffleMode,
    ShuffleMode? serverShuffleMode,
    required this.repeatMode,
    required this.streamMode,
    required this.bitrateKbps,
    required this.streamConnected,
    required this.streamRttMs,
    required this.queueSource,
    required this.queueSourcePlaylistId,
    required this.localPlaybackSource,
    required this.isLocalPlayback,
  }) : localShuffleMode = shuffleScope == ActionScope.local
           ? shuffleMode
           : localShuffleMode ?? ShuffleMode.off,
       serverShuffleMode = shuffleScope == ActionScope.server
           ? shuffleMode
           : serverShuffleMode ?? ShuffleMode.off;

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
  final RepeatMode repeatMode;
  final StreamMode streamMode;
  final double? bitrateKbps;
  final bool streamConnected;
  final int? streamRttMs;
  final PlaybackQueueSource queueSource;
  final String? queueSourcePlaylistId;
  final LocalPlaybackSource localPlaybackSource;
  final bool isLocalPlayback;

  ShuffleMode get shuffleMode => shuffleModeFor(shuffleScope);

  ShuffleMode shuffleModeFor(ActionScope scope) =>
      scope == ActionScope.local ? localShuffleMode : serverShuffleMode;

  bool get hasPlaylistSource =>
      (queueSourcePlaylistId?.trim().isNotEmpty ?? false) &&
      (queueSource == PlaybackQueueSource.playlist ||
          (queueSource == PlaybackQueueSource.offline &&
              localPlaybackSource == LocalPlaybackSource.playlist));

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
    RepeatMode? repeatMode,
    StreamMode? streamMode,
    double? bitrateKbps,
    bool? streamConnected,
    int? streamRttMs,
    PlaybackQueueSource? queueSource,
    Object? queueSourcePlaylistId = _unset,
    LocalPlaybackSource? localPlaybackSource,
    bool? isLocalPlayback,
  }) {
    final nextShuffleScope = shuffleScope ?? this.shuffleScope;
    return PlaybackState(
      track: track == _unset ? this.track : track as Track?,
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
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      streamConnected: streamConnected ?? this.streamConnected,
      streamRttMs: streamRttMs ?? this.streamRttMs,
      queueSource: queueSource ?? this.queueSource,
      queueSourcePlaylistId: queueSourcePlaylistId == _unset
          ? this.queueSourcePlaylistId
          : queueSourcePlaylistId as String?,
      localPlaybackSource: localPlaybackSource ?? this.localPlaybackSource,
      isLocalPlayback: isLocalPlayback ?? this.isLocalPlayback,
    );
  }
}
