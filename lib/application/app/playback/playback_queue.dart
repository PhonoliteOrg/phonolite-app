part of 'package:phonolite_app/application/app/app_controller.dart';

class _PlaybackQueue {
  final AppController _host;
  List<Track> _playQueue = <Track>[];
  int _playIndex = 0;
  bool _autoAdvanceInFlight = false;
  DateTime? _suppressAutoAdvanceUntil;
  DateTime? _ignoreCompleteUntil;
  OfflineQueueSource _offlineQueueSource = OfflineQueueSource.none;

  _PlaybackQueue(this._host);

  Future<void> playLikedTrack(String trackId) async {
    await _host.queueLiked(startTrackId: trackId);
  }

  Future<void> playLocalLikedTrack(String trackId) async {
    final tracks = _host.localLiked;

    if (tracks.isEmpty) {
      await _host.loadLocalLikedTracks();
    }

    await _host.playOfflineTrack(trackId, tracks: _host.localLiked, localLikedQueue: true);
  }

  Future<void> queueLocalPlaylist(String playlistId, {String? startTrackId}) async {
    if (_host._playbackState.shuffleMode != ShuffleMode.off) {
      if (_host._playbackState.shuffleScope == ActionScope.local) {
        await _host.queueLocalShuffle(
          playlistId: _host._playbackState.shuffleMode == ShuffleMode.currentPlaylist ? playlistId : null,
          startTrackId: startTrackId,
        );

        return;
      }

      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }

    await _host.loadLocalPlaylistTracks(playlistId);

    final tracks = _host.localPlaylistTracks;

    if (tracks.isEmpty) {
      _host._pushMessage('No downloaded tracks found for local playlist');

      return;
    }

    _setQueue(
      tracks,
      startTrackId: startTrackId,
      queueSource: PlaybackQueueSource.offline,
      queueSourcePlaylistId: playlistId,
      offlineQueueSource: OfflineQueueSource.localPlaylist,
    );
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    _armAutoAdvanceGuard();
    await _host._playCurrent();
  }

  Future<void> playLocalPlaylistFromTop(String playlistId) async {
    if (_host._playbackState.shuffleMode != ShuffleMode.off) {
      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }

    await _host.queueLocalPlaylist(playlistId);
  }

  Future<void> playOfflineTrack(String trackId, {List<Track>? tracks, bool localLikedQueue = false}) async {
    if (_host._playbackState.shuffleMode != ShuffleMode.off) {
      if (_host._playbackState.shuffleScope == ActionScope.local) {
        final mode = _host._playbackState.shuffleMode;

        if (await _localShuffleCanStartFromTrack(mode, trackId)) {
          await _host.queueLocalShuffle(startTrackId: trackId);

          return;
        }
      }

      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    }

    final available = <String, Track>{
      for (final track in _host.offlineTracks) track.id: track,
      for (final download in _host.availableOfflineDownloads) ...{
        download.track.id: download.track,
        if (download.localTrackId != null)
          download.localTrackId!: download.track.copyWith(
            id: download.localTrackId!,
            localId: download.localTrackId,
            serverBaseUrl: download.serverBaseUrl,
            serverTrackId: download.track.serverTrackId ?? download.track.id,
          ),
      },
    };
    final queue = (tracks ?? available.values.toList())
        .where(
          (track) => available.containsKey(track.id) || (track.localId != null && available.containsKey(track.localId)),
        )
        .toList(growable: false);

    if (queue.isEmpty || !available.containsKey(trackId)) {
      _host._pushMessage('Downloaded track is not available on this device.');

      return;
    }

    _setQueue(
      queue,
      startTrackId: trackId,
      queueSource: PlaybackQueueSource.offline,
      offlineQueueSource: localLikedQueue ? OfflineQueueSource.localLiked : OfflineQueueSource.tracks,
    );
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    _armAutoAdvanceGuard();
    await _host._playCurrent();
  }

  Future<void> queueAlbum(String albumId, {String? startTrackId}) async {
    if (!_host._requireServer('playing albums from the server')) {
      return;
    }

    try {
      if (_host._playbackState.shuffleMode != ShuffleMode.off &&
          _host._playbackState.shuffleScope != ActionScope.server) {
        _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }

      if (startTrackId != null) {
        await _host._maybeDisableShuffleForTrackSelection(startTrackId);

        if (_host._playbackState.shuffleMode != ShuffleMode.off &&
            _host._playbackState.shuffleMode != ShuffleMode.liked) {
          _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
        }
      }

      if (_host._playbackState.shuffleMode != ShuffleMode.off) {
        String? artistId;
        String? albumShuffleId;

        if (_host._playbackState.shuffleMode == ShuffleMode.album) {
          albumShuffleId = albumId;
        } else if (_host._playbackState.shuffleMode == ShuffleMode.artist) {
          final album = await _host.connection.fetchAlbumById(albumId);

          artistId = album.artistId;
        }

        await _host.queueShuffle(
          scope: 'library',
          artistId: artistId,
          albumId: albumShuffleId,
          startTrackId: startTrackId,
        );

        return;
      }

      _host._pushMessage('Queue album: $albumId${startTrackId == null ? '' : ' (start $startTrackId)'}');

      final tracks = _host._lastAlbumId == albumId && _host._tracks.isNotEmpty
          ? List<Track>.of(_host._tracks)
          : await _host.connection.fetchTracks(albumId);

      if (tracks.isEmpty) {
        _host._pushMessage('No tracks found for album');

        return;
      }

      final normalized = tracks
          .map((track) => (track.albumId == null || track.albumId!.isEmpty) ? track.copyWith(albumId: albumId) : track)
          .toList();

      _setQueue(normalized, startTrackId: startTrackId, queueSource: PlaybackQueueSource.none);
      _armAutoAdvanceGuard();
      await _host._playCurrent();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'queue album');
    } catch (err) {
      _host._pushMessage('Failed to queue album: $err');
    }
  }

  Future<void> queuePlaylist(String playlistId, {String? startTrackId}) async {
    if (!_host._requireServer('playing playlists from the server')) {
      return;
    }

    try {
      if (_host._playbackState.shuffleMode != ShuffleMode.off &&
          _host._playbackState.shuffleScope != ActionScope.server) {
        _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }

      if (startTrackId != null) {
        await _host._maybeDisableShuffleForTrackSelection(startTrackId);
      }

      if (_host._playbackState.shuffleMode != ShuffleMode.off) {
        if (_host._playbackState.shuffleMode == ShuffleMode.all) {
          await _host.queueShuffle(scope: 'library', startTrackId: startTrackId);

          return;
        }

        if ((_host._playbackState.shuffleMode == ShuffleMode.album ||
                _host._playbackState.shuffleMode == ShuffleMode.artist) &&
            startTrackId != null) {
          final context = await _host._resolveAlbumArtistForTrack(startTrackId);

          await _host.queueShuffle(
            scope: 'library',
            artistId: context.artistId,
            albumId: context.albumId,
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.playlist,
            queueSourcePlaylistIdOverride: playlistId,
          );

          if (_playQueue.isNotEmpty) {
            _host._updatePlayback(
              queueSource: PlaybackQueueSource.playlist,
              queueSourcePlaylistId: playlistId,
              nowPlaying: false,
            );
          }
        } else {
          await _host.queueShuffle(
            scope: 'playlist',
            playlistId: playlistId,
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.playlist,
            queueSourcePlaylistIdOverride: playlistId,
          );

          if (_playQueue.isNotEmpty) {
            _host._updatePlayback(
              queueSource: PlaybackQueueSource.playlist,
              queueSourcePlaylistId: playlistId,
              nowPlaying: false,
            );
          }
        }

        return;
      }

      _host._pushMessage('Queue playlist: $playlistId${startTrackId == null ? '' : ' (start $startTrackId)'}');

      final tracks = (_host._currentPlaylistId == playlistId && _host._playlistTracks.isNotEmpty)
          ? _host._playlistTracks
          : await _host.connection.fetchPlaylistTracks(playlistId);

      if (tracks.isEmpty) {
        _host._pushMessage('No tracks found for playlist');

        return;
      }

      final normalized = _host._normalizeQueueTracks(tracks);

      _setQueue(
        normalized,
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.playlist,
        queueSourcePlaylistId: playlistId,
      );
      _armAutoAdvanceGuard();
      await _host._playCurrent();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'queue playlist');
    } catch (err) {
      _host._pushMessage('Failed to queue playlist: $err');
    }
  }

  Future<void> playPlaylistFromTop(String playlistId) async {
    if (_host._playbackState.shuffleMode != ShuffleMode.off) {
      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    }

    await _host.queuePlaylist(playlistId);
  }

  Future<void> queueLiked({String? startTrackId}) async {
    if (!_host._requireServer('playing liked songs from the server')) {
      return;
    }

    try {
      if (_host._playbackState.shuffleMode != ShuffleMode.off &&
          _host._playbackState.shuffleScope != ActionScope.server) {
        _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }

      if (_host._playbackState.shuffleMode != ShuffleMode.off &&
          _host._playbackState.shuffleMode != ShuffleMode.liked) {
        _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
      }

      if (_host._playbackState.shuffleMode != ShuffleMode.liked) {
        _host._queueShuffleMode = ShuffleMode.off;
        _host._queueShuffleScope = null;
        _host._queueShuffleArtistId = null;
        _host._queueShuffleAlbumId = null;
        _host._queueShufflePlaylistId = null;
      }

      if (startTrackId != null) {
        await _host._maybeDisableShuffleForTrackSelection(startTrackId);
      }

      if (_host._playbackState.shuffleMode != ShuffleMode.off) {
        if ((_host._playbackState.shuffleMode == ShuffleMode.album ||
                _host._playbackState.shuffleMode == ShuffleMode.artist) &&
            startTrackId != null) {
          final context = await _host._resolveAlbumArtistForTrack(startTrackId);

          await _host.queueShuffle(
            scope: 'library',
            artistId: context.artistId,
            albumId: context.albumId,
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.liked,
          );
        } else {
          await _host.queueShuffle(
            scope: 'liked',
            startTrackId: startTrackId,
            queueSourceOverride: PlaybackQueueSource.liked,
          );
        }

        return;
      }

      _host._pushMessage('Queue liked${startTrackId == null ? '' : ' (start $startTrackId)'}');

      final tracks = _host._liked.isNotEmpty ? _host._liked : await _host.connection.fetchLikedTracks();

      if (tracks.isEmpty) {
        _host._pushMessage('No liked tracks found');

        return;
      }

      final normalized = _host._normalizeQueueTracks(tracks);

      _setQueue(normalized, startTrackId: startTrackId, queueSource: PlaybackQueueSource.liked);
      _armAutoAdvanceGuard();
      await _host._playCurrent();
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'queue liked');
    } catch (err) {
      _host._pushMessage('Failed to queue liked: $err');
    }
  }

  Future<bool> _localShuffleCanStartFromTrack(ShuffleMode mode, String trackId) async {
    switch (mode) {
      case ShuffleMode.all:
      case ShuffleMode.artist:
      case ShuffleMode.album:
        return _host._localLibrary.track(trackId) != null;
      case ShuffleMode.liked:
        return _host._localTrackIsLiked(trackId);
      case ShuffleMode.custom:
        await _host._ensureCustomShuffleSettingsLoaded();
        final track = _host._localLibrary.track(trackId);
        if (track == null) {
          return false;
        }

        final artistIds = _host._customShuffleSettings.localArtistIds.toSet();
        final genres = _host._customShuffleSettings.localGenres.map((genre) => genre.toLowerCase()).toSet();

        if (artistIds.isEmpty && genres.isEmpty) {
          return false;
        }

        return _host._localLibrary.matchesCustomShuffle(track, artistIds: artistIds, genres: genres);
      case ShuffleMode.currentPlaylist:
      case ShuffleMode.off:
        return false;
    }
  }

  void _setQueue(
    List<Track> tracks, {
    String? startTrackId,
    required PlaybackQueueSource queueSource,
    String? queueSourcePlaylistId,
    OfflineQueueSource offlineQueueSource = OfflineQueueSource.none,
  }) {
    _playQueue = tracks;
    _offlineQueueSource = queueSource == PlaybackQueueSource.offline ? offlineQueueSource : OfflineQueueSource.none;

    if (startTrackId != null) {
      final idx = tracks.indexWhere((track) => track.id == startTrackId);

      _playIndex = idx >= 0 ? idx : 0;
    } else {
      _playIndex = 0;
    }

    _autoAdvanceInFlight = false;
    _host._updatePlayback(
      queueSource: queueSource,
      queueSourcePlaylistId:
          queueSource == PlaybackQueueSource.playlist ||
              (queueSource == PlaybackQueueSource.offline && offlineQueueSource == OfflineQueueSource.localPlaylist)
          ? queueSourcePlaylistId
          : null,
      localPlaybackSource: queueSource == PlaybackQueueSource.offline
          ? _localPlaybackSourceFor(offlineQueueSource)
          : LocalPlaybackSource.none,
      nowPlaying: false,
    );
  }

  LocalPlaybackSource _localPlaybackSourceFor(OfflineQueueSource source) {
    return switch (source) {
      OfflineQueueSource.localLiked => LocalPlaybackSource.liked,
      OfflineQueueSource.localPlaylist => LocalPlaybackSource.playlist,
      OfflineQueueSource.tracks => LocalPlaybackSource.library,
      OfflineQueueSource.none => LocalPlaybackSource.none,
    };
  }

  void _armAutoAdvanceGuard([Duration duration = const Duration(milliseconds: 1200)]) {
    _ignoreCompleteUntil = DateTime.now().add(duration);
  }

  void _syncPlayIndexWithCurrent() {
    if (_playQueue.isEmpty) {
      return;
    }

    final currentId = _host._playbackState.track?.id;

    if (currentId == null || currentId.isEmpty) {
      return;
    }

    final idx = _playQueue.indexWhere((track) => track.id == currentId);

    if (idx >= 0 && idx != _playIndex) {
      _playIndex = idx;
    }
  }

  List<String> _buildQueueIds(String currentId, int count) {
    if (_playQueue.isEmpty) {
      return <String>[currentId];
    }

    final startIndex = _playQueue.indexWhere((track) => track.id == currentId);
    final index = startIndex >= 0 ? startIndex : _playIndex;
    final total = _playQueue.length;
    final limit = count.clamp(1, total);
    final ids = <String>[];

    for (var i = 0; i < limit; i++) {
      final idx = (index + i) % total;

      ids.add(_playQueue[idx].id);
    }

    return ids;
  }

  void _handleTrackFinished() {
    if (_host._disposed) {
      return;
    }

    if (!_host._wantsPlayback) {
      return;
    }

    if (_autoAdvanceInFlight) {
      return;
    }

    final now = DateTime.now();
    final seekStillResolving =
        _host._isScrubbing ||
        _host._seeking ||
        (_suppressAutoAdvanceUntil != null &&
            now.isBefore(_suppressAutoAdvanceUntil!) &&
            (!_host._audioOutputStarted || _host._playbackState.isLoading));

    if (seekStillResolving) {
      _autoAdvanceInFlight = false;

      return;
    }

    if (_ignoreCompleteUntil != null && now.isBefore(_ignoreCompleteUntil!)) {
      _autoAdvanceInFlight = false;

      return;
    }

    _autoAdvanceInFlight = true;
    _host._listeningSessionContext = null;

    if (_host._playbackState.repeatMode == RepeatMode.one) {
      final track = _host._playbackState.track;

      if (track == null) {
        _host._wantsPlayback = false;
        _host._updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
        _autoAdvanceInFlight = false;

        return;
      }

      Future<void> repeatFinishedTrack() async {
        if (_playQueue.isEmpty) {
          _host._updatePlayback(
            track: track,
            isPlaying: true,
            position: Duration.zero,
            duration: Duration(milliseconds: track.durationMs),
            bufferRatio: 0.0,
          );
          _host._startPlayback(track);
          _autoAdvanceInFlight = false;

          return;
        }

        await _host._playCurrent();
      }

      repeatFinishedTrack();

      return;
    }

    if (_playQueue.isEmpty) {
      if (_host._playbackState.shuffleMode != ShuffleMode.off) {
        Future<void> continueShuffle() async {
          final ensured = await _host._ensureShuffleQueue(play: true);

          if (!ensured) {
            _host._wantsPlayback = false;
            _host._updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
          }

          _autoAdvanceInFlight = false;
        }

        continueShuffle();

        return;
      }

      _host._updatePlayback(isPlaying: false, position: Duration.zero, bufferRatio: 0.0);
      _host._wantsPlayback = false;
      _autoAdvanceInFlight = false;

      return;
    }

    _host.nextTrack(fromAutoAdvance: true);
  }

  void _maybeAutoAdvance(Duration position, Duration bufferedAhead) {
    // Disable position-based auto-advance; rely on audio engine completion.
    return;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PlaybackQueueFacade {
  _PlaybackQueue get _queueCoordinator;

  List<Track> get _playQueue => _queueCoordinator._playQueue;

  set _playQueue(List<Track> value) => _queueCoordinator._playQueue = value;

  int get _playIndex => _queueCoordinator._playIndex;

  set _playIndex(int value) => _queueCoordinator._playIndex = value;

  set _autoAdvanceInFlight(bool value) => _queueCoordinator._autoAdvanceInFlight = value;

  set _suppressAutoAdvanceUntil(DateTime? value) => _queueCoordinator._suppressAutoAdvanceUntil = value;

  set _ignoreCompleteUntil(DateTime? value) => _queueCoordinator._ignoreCompleteUntil = value;

  OfflineQueueSource get _offlineQueueSource => _queueCoordinator._offlineQueueSource;

  set _offlineQueueSource(OfflineQueueSource value) => _queueCoordinator._offlineQueueSource = value;

  Future<void> playLikedTrack(String trackId) => _queueCoordinator.playLikedTrack(trackId);

  Future<void> playLocalLikedTrack(String trackId) => _queueCoordinator.playLocalLikedTrack(trackId);

  Future<void> queueLocalPlaylist(String playlistId, {String? startTrackId}) =>
      _queueCoordinator.queueLocalPlaylist(playlistId, startTrackId: startTrackId);

  Future<void> playLocalPlaylistFromTop(String playlistId) => _queueCoordinator.playLocalPlaylistFromTop(playlistId);

  Future<void> playOfflineTrack(String trackId, {List<Track>? tracks, bool localLikedQueue = false}) =>
      _queueCoordinator.playOfflineTrack(trackId, tracks: tracks, localLikedQueue: localLikedQueue);

  Future<void> queueAlbum(String albumId, {String? startTrackId}) =>
      _queueCoordinator.queueAlbum(albumId, startTrackId: startTrackId);

  Future<void> queuePlaylist(String playlistId, {String? startTrackId}) =>
      _queueCoordinator.queuePlaylist(playlistId, startTrackId: startTrackId);

  Future<void> playPlaylistFromTop(String playlistId) => _queueCoordinator.playPlaylistFromTop(playlistId);

  Future<void> queueLiked({String? startTrackId}) => _queueCoordinator.queueLiked(startTrackId: startTrackId);

  void _setQueue(
    List<Track> tracks, {
    String? startTrackId,
    required PlaybackQueueSource queueSource,
    String? queueSourcePlaylistId,
    OfflineQueueSource offlineQueueSource = OfflineQueueSource.none,
  }) => _queueCoordinator._setQueue(
    tracks,
    startTrackId: startTrackId,
    queueSource: queueSource,
    queueSourcePlaylistId: queueSourcePlaylistId,
    offlineQueueSource: offlineQueueSource,
  );

  void _armAutoAdvanceGuard([Duration duration = const Duration(milliseconds: 1200)]) =>
      _queueCoordinator._armAutoAdvanceGuard(duration);

  void _syncPlayIndexWithCurrent() => _queueCoordinator._syncPlayIndexWithCurrent();

  List<String> _buildQueueIds(String currentId, int count) => _queueCoordinator._buildQueueIds(currentId, count);

  void _handleTrackFinished() => _queueCoordinator._handleTrackFinished();

  void _maybeAutoAdvance(Duration position, Duration bufferedAhead) =>
      _queueCoordinator._maybeAutoAdvance(position, bufferedAhead);
}
