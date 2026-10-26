part of '../app_controller.dart';

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _ShuffleFacade {
  _ShuffleCoordinator get _shuffleCoordinator;

  ShuffleMode get _queueShuffleMode => _shuffleCoordinator._queueShuffleMode;

  set _queueShuffleMode(ShuffleMode value) => _shuffleCoordinator._queueShuffleMode = value;

  set _queueShuffleScope(String? value) => _shuffleCoordinator._queueShuffleScope = value;

  set _queueShufflePlaylistId(String? value) => _shuffleCoordinator._queueShufflePlaylistId = value;

  set _queueShuffleArtistId(String? value) => _shuffleCoordinator._queueShuffleArtistId = value;

  set _queueShuffleAlbumId(String? value) => _shuffleCoordinator._queueShuffleAlbumId = value;

  LocalLibrarySelection get _localLibrary => _shuffleCoordinator._localLibrary;

  Future<void> queueShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
  }) => _shuffleCoordinator.queueShuffle(
    scope: scope,
    playlistId: playlistId,
    artistId: artistId,
    albumId: albumId,
    play: play,
    startTrackId: startTrackId,
    queueSourceOverride: queueSourceOverride,
    queueSourcePlaylistIdOverride: queueSourcePlaylistIdOverride,
  );

  Future<void> queueServerShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
  }) => _shuffleCoordinator.queueServerShuffle(
    scope: scope,
    playlistId: playlistId,
    artistId: artistId,
    albumId: albumId,
    play: play,
    startTrackId: startTrackId,
    queueSourceOverride: queueSourceOverride,
    queueSourcePlaylistIdOverride: queueSourcePlaylistIdOverride,
  );

  Future<void> queueLocalShuffle({
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
  }) => _shuffleCoordinator.queueLocalShuffle(
    playlistId: playlistId,
    artistId: artistId,
    albumId: albumId,
    play: play,
    startTrackId: startTrackId,
  );

  Future<bool> _ensureShuffleQueue({bool play = true}) => _shuffleCoordinator._ensureShuffleQueue(play: play);

  Future<bool> _ensureAlbumQueueFromCurrent() => _shuffleCoordinator._ensureAlbumQueueFromCurrent();

  Future<({String? artistId, String? albumId})> _resolveAlbumArtistForTrack(String trackId) =>
      _shuffleCoordinator._resolveAlbumArtistForTrack(trackId);

  Future<void> _maybeDisableShuffleForTrackSelection(String trackId) =>
      _shuffleCoordinator._maybeDisableShuffleForTrackSelection(trackId);

  Future<void> _refreshCustomShuffleQueueIfNeeded() => _shuffleCoordinator._refreshCustomShuffleQueueIfNeeded();
}
