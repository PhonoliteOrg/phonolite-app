part of '../app_controller.dart';

class _ShuffleCoordinator {
  final AppController _host;
  final Random _shuffleRandom = Random();
  ShuffleMode _queueShuffleMode = ShuffleMode.off;
  String? _queueShuffleScope;
  String? _queueShufflePlaylistId;
  String? _queueShuffleArtistId;
  String? _queueShuffleAlbumId;
  bool _customShuffleRefreshInFlight = false;
  bool _customShuffleRefreshQueued = false;
  final _serverShuffleRequests = RequestGeneration();
  final _serverNavigationRequests = RequestGeneration();
  final String _serverClientId = _newShuffleIdentifier();
  ServerShuffleDeck? _serverDeck;
  int? _serverDeckSessionRevision;
  bool _serverDeckExpired = false;
  bool _serverDeckReady = false;
  final _serverNavigation = SerialActionQueue();

  _ShuffleCoordinator(this._host);

  LocalLibrarySelection get _localLibrary =>
      LocalLibrarySelection(tracks: _host.offlineTracks, artists: _host.offlineLibrarySnapshot.artistGroups);

  Future<void> queueShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
  }) {
    return _host.queueServerShuffle(
      scope: scope,
      playlistId: playlistId,
      artistId: artistId,
      albumId: albumId,
      play: play,
      startTrackId: startTrackId,
      queueSourceOverride: queueSourceOverride,
      queueSourcePlaylistIdOverride: queueSourcePlaylistIdOverride,
    );
  }

  Future<void> queueServerShuffle({
    required String scope,
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    PlaybackQueueSource? queueSourceOverride,
    String? queueSourcePlaylistIdOverride,
    bool preserveNavigation = false,
  }) async {
    if (!_host._requireServer('starting server shuffle')) {
      return;
    }

    _clearServerShuffleSession(cancelNavigation: !preserveNavigation);
    final request = _serverShuffleRequests.current;
    final revision = _host.connection.sessionRevision;

    bool isCurrent() =>
        _serverShuffleRequests.isCurrent(request) && _host._sessionCoordinator._isServerSessionCurrent(revision);

    final selection = _host._playbackCoordinator._beginShuffleSelection(enabled: play);
    try {
      final mode = _host._playbackState.shuffleMode;
      if (mode == ShuffleMode.off || _host._playbackState.shuffleScope != ActionScope.server) {
        return;
      }

      if (scope == 'playlist' && (playlistId == null || playlistId.isEmpty)) {
        _host._pushMessage('No playlist selected for shuffle');

        return;
      }

      if (scope != 'playlist' && scope != 'liked' && mode == ShuffleMode.artist && artistId == null) {
        _host._pushMessage('Select an artist to shuffle');

        return;
      }

      if (scope != 'playlist' && scope != 'liked' && mode == ShuffleMode.album && albumId == null) {
        _host._pushMessage('Select an album to shuffle');

        return;
      }

      if (mode == ShuffleMode.custom) {
        await _host._ensureCustomShuffleSettingsLoaded();
        if (!isCurrent()) {
          return;
        }
      }

      final queueSource = queueSourceOverride ?? _serverShuffleQueueSource(scope);
      final queuePlaylistId = queueSource == PlaybackQueueSource.playlist
          ? (queueSourcePlaylistIdOverride ?? playlistId)
          : null;
      final queryMode = scope == 'playlist'
          ? 'playlist'
          : scope == 'liked'
          ? 'liked'
          : _shuffleQueryMode(mode);
      final first = await _host.connection.createShuffleSession(
        mode: queryMode,
        clientId: _serverClientId,
        requestId: _newShuffleIdentifier(),
        artistId: artistId,
        albumId: albumId,
        artistIds: mode == ShuffleMode.custom ? _host._customShuffleSettings.artistIds : const [],
        genres: mode == ShuffleMode.custom ? _host._customShuffleSettings.genres : const [],
        playlistId: playlistId,
        startTrackId: startTrackId,
      );
      if (!isCurrent()) {
        _releaseServerShuffleSession(first.sessionId, revision);

        return;
      }

      final deck = ServerShuffleDeck(
        first,
        load: (offset) async {
          try {
            return await _host.connection.fetchShuffleSessionPage(
              first.sessionId,
              clientId: _serverClientId,
              offset: offset,
            );
          } on ApiException catch (error) {
            if (error.statusCode != 404 || !_host._resumeCoordinator.hasDurableDeck(first.sessionId)) {
              rethrow;
            }

            return _host.connection.fetchAccountPlaybackDeck(first.sessionId, offset: offset);
          }
        },
      );
      _serverDeck = deck;
      _serverDeckSessionRevision = revision;
      final available = await deck.initialize(play: play, currentTrackId: startTrackId);
      if (!isCurrent() || !identical(_serverDeck, deck)) {
        return;
      }

      if (!available) {
        _clearServerShuffleSession();
        _host._pushMessage('No tracks found for shuffle');

        return;
      }

      _rememberShuffleContext(scope: scope, playlistId: playlistId, artistId: artistId, albumId: albumId);
      _serverDeckReady = true;
      _host._setQueue(
        _host._normalizeQueueTracks(deck.tracks),
        startTrackId: startTrackId,
        queueSource: queueSource,
        queueSourcePlaylistId: queuePlaylistId,
        preserveServerShuffle: true,
      );
      _applyServerShuffleWindow(deck);
      _host._armAutoAdvanceGuard();
      if (play) {
        await _host._playCurrent();
      }
    } on ApiException catch (err) {
      if (!isCurrent()) {
        return;
      }

      _clearServerShuffleSession();
      _host._handleApiError(err, context: 'queue shuffle');
    } on Object catch (err) {
      if (!isCurrent()) {
        return;
      }

      _clearServerShuffleSession();
      _host._pushMessage('Failed to queue shuffle: $err');
    } finally {
      _host._playbackCoordinator._finishShuffleSelection(selection);
    }
  }

  void _clearServerShuffleSession({bool cancelNavigation = true}) {
    if (cancelNavigation) {
      _host._playbackCoordinator._finishShuffleSelection(_host._playbackCoordinator._shuffleSelection);
    }

    if (cancelNavigation) {
      _serverNavigationRequests.advance();
    }

    _serverShuffleRequests.advance();
    final deck = _serverDeck;
    final revision = _serverDeckSessionRevision;
    _serverDeck = null;
    _serverDeckSessionRevision = null;
    _serverDeckExpired = false;
    _serverDeckReady = false;
    _host._shuffleArtworkPreloader?.clear();
    _preloadNativeArtwork(const []);
    deck?.close();
    if (deck != null && revision != null) {
      _releaseServerShuffleSession(deck.sessionId, revision);
    }
  }

  void _releaseServerShuffleSession(String sessionId, int revision) {
    if (_host.connection.sessionRevision != revision || _host.connection.token == null) {
      return;
    }

    unawaited(
      _host.connection
          .releaseShuffleSession(sessionId, clientId: _serverClientId)
          .catchError((Object error) => AppLogger.debug('Shuffle session cleanup skipped: $error')),
    );
  }

  void _applyServerShuffleWindow(ServerShuffleDeck deck) {
    final loaded = {for (final track in _host._playQueue) track.id: track};
    final tracks = _host._normalizeQueueTracks(deck.tracks.map((track) => loaded[track.id] ?? track).toList());
    _host._playQueue = _host.connection.projectServerTracks(tracks);
    _host._playIndex = deck.queueIndex;
    _preloadServerShuffleArtwork();
  }

  void _prefetchServerShuffle() {
    final deck = _serverDeck;
    if (deck == null) {
      return;
    }

    final revision = _host.connection.sessionRevision;

    Future<void> refill() async {
      try {
        await deck.prefetch();
        if (_host._sessionCoordinator._isServerSessionCurrent(revision) && identical(_serverDeck, deck)) {
          _applyServerShuffleWindow(deck);
        }
      } on Object catch (error) {
        if (identical(_serverDeck, deck) && error is ApiException && error.statusCode == 404) {
          _serverDeckExpired = true;
        }

        if (identical(_serverDeck, deck)) {
          AppLogger.debug('Shuffle prefetch deferred: $error');
        }
      }
    }

    unawaited(refill());
  }

  Future<void> _navigateServerShuffle(int direction) {
    final request = _serverNavigationRequests.current;

    final revision = _host.connection.sessionRevision;

    Future<void> move() async {
      if (!_serverNavigationRequests.isCurrent(request) ||
          !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
        return;
      }

      final ensured = await _ensureServerShuffleQueue(play: false, preserveNavigation: true);
      if (!ensured ||
          !_serverNavigationRequests.isCurrent(request) ||
          !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
        return;
      }

      final deck = _serverDeck;
      if (deck == null) {
        return;
      }

      var moved = false;
      try {
        if (!_serverDeckExpired) {
          moved = await deck.move(direction);
        }
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }

        if (identical(_serverDeck, deck)) {
          _serverDeckExpired = true;
        }
      }

      if (!identical(_serverDeck, deck) || !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
        return;
      }

      if (moved) {
        _applyServerShuffleWindow(deck);
        await _host._playCurrent();
      } else if (direction > 0 || _serverDeckExpired) {
        // Repeat-off has always advanced through repeat-all queues in this app.
        // A new pass begins only after the complete server deck is exhausted.
        await queueServerShuffle(
          preserveNavigation: true,
          scope: _queueShuffleScope ?? 'library',
          playlistId: _queueShufflePlaylistId,
          artistId: _queueShuffleArtistId,
          albumId: _queueShuffleAlbumId,
          queueSourceOverride: _host._playbackState.queueSource,
          queueSourcePlaylistIdOverride: _host._playbackState.queueSourcePlaylistId,
        );
        if (_serverDeck == null && _host._sessionCoordinator._isServerSessionCurrent(revision)) {
          _host._wantsPlayback = false;
          _host._updatePlayback(isPlaying: false, isLoading: false);
        }
      }
    }

    return _serverNavigation.add(move);
  }

  Future<void> queueLocalShuffle({
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
    bool preserveContext = false,
    String? avoidTrackId,
  }) async {
    final playback = _host._playbackCoordinator;
    final selection = play ? playback._beginShuffleSelection() : playback._shuffleSelection;
    try {
      final mode = _host._playbackState.shuffleMode;

      if (mode == ShuffleMode.off) {
        _host._pushMessage('Shuffle is off');

        return;
      }

      if (_host._playbackState.shuffleScope != ActionScope.local) {
        _host._pushMessage('Local shuffle requires a local playback scope');

        return;
      }

      List<Track> tracks;
      OfflineQueueSource offlineSource;
      String? sourcePlaylistId;
      String contextScope;
      String? contextArtistId;
      String? contextAlbumId;

      if (mode == ShuffleMode.currentPlaylist) {
        sourcePlaylistId =
            playlistId ??
            (_host._playbackState.queueSource == PlaybackQueueSource.offline
                ? _host._playbackState.queueSourcePlaylistId
                : null);

        if (sourcePlaylistId == null || sourcePlaylistId.isEmpty) {
          _host._pushMessage('Select a local playlist to shuffle');

          return;
        }

        await _host.loadLocalPlaylistTracks(sourcePlaylistId);
        if (!playback._isShuffleSelectionCurrent(selection)) {
          return;
        }

        tracks = _host.localPlaylistTracks;
        offlineSource = OfflineQueueSource.localPlaylist;
        contextScope = 'localPlaylist';
      } else if (mode == ShuffleMode.liked) {
        if (_host.localLiked.isEmpty) {
          await _host.loadLocalLikedTracks();
          if (!playback._isShuffleSelectionCurrent(selection)) {
            return;
          }
        }

        tracks = _host.localLiked;
        offlineSource = OfflineQueueSource.localLiked;
        contextScope = 'localLiked';
      } else if (mode == ShuffleMode.artist) {
        contextArtistId = preserveContext
            ? artistId
            : _resolveLocalShuffleArtistId(startTrackId: startTrackId, artistId: artistId);

        if (contextArtistId == null || contextArtistId.isEmpty) {
          _host._pushMessage('Select a local artist to shuffle');

          return;
        }

        final group = _localLibrary.artist(contextArtistId);

        if (group == null) {
          _host._pushMessage('No downloaded tracks found for local artist');

          return;
        }

        tracks = group.tracksForArtist;
        offlineSource = OfflineQueueSource.tracks;
        contextScope = 'localArtist';
      } else if (mode == ShuffleMode.album) {
        contextAlbumId = preserveContext
            ? albumId
            : _resolveLocalShuffleAlbumId(startTrackId: startTrackId, albumId: albumId);

        if (contextAlbumId == null || contextAlbumId.isEmpty) {
          _host._pushMessage('Select a local album to shuffle');

          return;
        }

        final group = _localLibrary.album(contextAlbumId);

        if (group == null) {
          _host._pushMessage('No downloaded tracks found for local album');

          return;
        }

        tracks = group.tracks;
        offlineSource = OfflineQueueSource.tracks;
        contextScope = 'localAlbum';
      } else if (mode == ShuffleMode.custom) {
        await _host._ensureCustomShuffleSettingsLoaded();
        if (!playback._isShuffleSelectionCurrent(selection)) {
          return;
        }

        final artistIds = _host._customShuffleSettings.localArtistIds.toSet();
        final genres = _host._customShuffleSettings.localGenres.map((genre) => genre.toLowerCase()).toSet();

        if (artistIds.isEmpty && genres.isEmpty) {
          _host._pushMessage('Local custom shuffle has no filters.');

          return;
        }

        tracks = _host.offlineTracks
            .where((track) => _localLibrary.matchesCustomShuffle(track, artistIds: artistIds, genres: genres))
            .toList(growable: false);
        offlineSource = OfflineQueueSource.tracks;
        contextScope = 'localCustom';
      } else {
        tracks = _host.offlineTracks;
        offlineSource = OfflineQueueSource.tracks;
        contextScope = 'localLibrary';
      }

      if (tracks.isEmpty) {
        _host._pushMessage('No downloaded tracks found for shuffle');

        return;
      }

      _rememberShuffleContext(
        scope: contextScope,
        playlistId: sourcePlaylistId,
        artistId: contextArtistId,
        albumId: contextAlbumId,
      );
      _host._setQueue(
        _shuffleTracks(tracks, avoidTrackId: avoidTrackId),
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.offline,
        queueSourcePlaylistId: sourcePlaylistId,
        offlineQueueSource: offlineSource,
      );
      _host._armAutoAdvanceGuard();

      if (play) {
        await _host._playCurrent();
      }
    } on Object catch (err) {
      _host._pushMessage('Failed to queue local shuffle: $err');
    } finally {
      playback._finishShuffleSelection(selection);
    }
  }

  PlaybackQueueSource _serverShuffleQueueSource(String scope) {
    if (scope == 'playlist') {
      return PlaybackQueueSource.playlist;
    }

    if (scope == 'liked' || _host._playbackState.shuffleMode == ShuffleMode.liked) {
      return PlaybackQueueSource.liked;
    }

    return PlaybackQueueSource.none;
  }

  void _rememberShuffleContext({required String scope, String? playlistId, String? artistId, String? albumId}) {
    _host._resumeCoordinator.rememberShuffle(
      scope: scope,
      playlistId: playlistId,
      artistId: artistId,
      albumId: albumId,
    );
    _queueShuffleMode = _host._playbackState.shuffleMode;
    _queueShuffleScope = scope;
    _queueShufflePlaylistId = playlistId;
    _queueShuffleArtistId = artistId;
    _queueShuffleAlbumId = albumId;
  }

  Future<bool> _ensureShuffleQueue({bool play = true}) async {
    if (_host._playbackState.shuffleScope == ActionScope.local) {
      return _ensureLocalShuffleQueue(play: play);
    }

    return _ensureServerShuffleQueue(play: play);
  }

  Future<bool> _ensureServerShuffleQueue({bool play = true, bool preserveNavigation = false}) async {
    if (_host._playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }

    if (_serverDeck == null && _host._resumeCoordinator.hasDeferredNavigation) {
      await _host._resumeCoordinator.restoreDeferredDeck();
    }

    if (_host._playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }

    final revision = _host.connection.sessionRevision;
    final request = _serverShuffleRequests.current;
    if (_serverDeck != null && !_serverDeckReady) {
      return false;
    }

    if (_serverDeck != null &&
        _host._playQueue.isNotEmpty &&
        _queueShuffleMode == _host._playbackState.shuffleMode &&
        _queueShuffleScope != null) {
      if (play && _host._playbackState.track == null) {
        final deck = _serverDeck!;
        if (deck.queueIndex < 0 && !await deck.move(1)) {
          return false;
        }

        if (!_serverShuffleRequests.isCurrent(request) ||
            !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
          return false;
        }

        _applyServerShuffleWindow(deck);
        await _host._playCurrent();
      }

      return true;
    }

    final context = await _resolveShuffleContext();
    if (context == null ||
        !_serverShuffleRequests.isCurrent(request) ||
        !_host._sessionCoordinator._isServerSessionCurrent(revision)) {
      return false;
    }

    final startTrackId = play ? null : _host._playbackState.track?.id;

    await queueServerShuffle(
      preserveNavigation: preserveNavigation,
      scope: context.scope,
      playlistId: context.playlistId,
      artistId: context.artistId,
      albumId: context.albumId,
      play: play,
      startTrackId: startTrackId,
    );

    return _serverShuffleRequests.current == request + 1 &&
        _serverDeck != null &&
        _host._sessionCoordinator._isServerSessionCurrent(revision);
  }

  Future<bool> _ensureLocalShuffleQueue({bool play = true}) async {
    if (_host._playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }

    if (_host._playQueue.isNotEmpty &&
        _queueShuffleMode == _host._playbackState.shuffleMode &&
        _queueShuffleScope != null &&
        _queueShuffleScope!.startsWith('local')) {
      if (play && _host._playbackState.track == null) {
        _host._playIndex = _host._playIndex.clamp(0, _host._playQueue.length - 1);
        await _host._playCurrent();
      }

      return true;
    }

    final startTrackId = play ? null : _host._playbackState.track?.id;
    final playlistId = _host._playbackState.shuffleMode == ShuffleMode.currentPlaylist
        ? (_queueShufflePlaylistId ??
              (_host._playbackState.queueSource == PlaybackQueueSource.offline
                  ? _host._playbackState.queueSourcePlaylistId
                  : null))
        : null;

    await _host.queueLocalShuffle(playlistId: playlistId, play: play, startTrackId: startTrackId);

    return _host._playQueue.isNotEmpty;
  }

  Future<bool> _ensureAlbumQueueFromCurrent() async {
    final current = _host._playbackState.track;
    if (current == null) {
      return false;
    }

    String? albumId = current.albumId;

    if (albumId == null || albumId.isEmpty) {
      try {
        final full = await _host.connection.fetchTrackById(current.id);

        albumId = full.albumId;
      } on Object catch (err) {
        _host._pushMessage('Failed to resolve album for track: $err');
      }
    }

    if (albumId == null || albumId.isEmpty) {
      _host._pushMessage('Track is missing album info');

      return false;
    }

    final tracks = await _host.connection.fetchTracks(albumId);

    if (tracks.isEmpty) {
      _host._pushMessage('No tracks found for album');

      return false;
    }

    _host._setQueue(
      tracks,
      startTrackId: current.id,
      queueSource: PlaybackQueueSource.none,
      sourceContext: PlaybackSourceContext(kind: 'album', id: albumId),
    );
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;

    return true;
  }

  Future<void> _refreshCustomShuffleQueueIfNeeded() async {
    if (_host._playbackState.shuffleMode != ShuffleMode.custom) {
      return;
    }

    final scope = _host._playbackState.shuffleScope;

    if (scope != ActionScope.server && scope != ActionScope.local) {
      return;
    }

    final hasActiveShuffle =
        _host._playQueue.isNotEmpty ||
        _queueShuffleScope != null ||
        _host._playbackState.isPlaying ||
        _host._playbackState.track != null;

    if (!hasActiveShuffle) {
      _queueShuffleMode = ShuffleMode.off;
      _queueShuffleScope = null;

      return;
    }

    if (scope == ActionScope.local) {
      if (_host._customShuffleSettings.localArtistIds.isEmpty && _host._customShuffleSettings.localGenres.isEmpty) {
        _host._pushMessage('Local custom shuffle has no filters.');
        _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);

        return;
      }

      await _refreshLocalCustomShuffleQueue();

      return;
    }

    await _refreshCustomShuffleQueue();
  }

  Future<void> _refreshCustomShuffleQueue() => _refreshCustomQueue(_refreshServerCustomQueue);

  Future<void> _refreshLocalCustomShuffleQueue() =>
      _refreshCustomQueue(() => _host.queueLocalShuffle(play: false, startTrackId: _host._playbackState.track?.id));

  Future<void> _refreshCustomQueue(Future<void> Function() refresh) async {
    if (_customShuffleRefreshInFlight) {
      _customShuffleRefreshQueued = true;

      return;
    }

    _customShuffleRefreshInFlight = true;

    try {
      do {
        _customShuffleRefreshQueued = false;
        await refresh();
      } while (_customShuffleRefreshQueued);
    } finally {
      _customShuffleRefreshInFlight = false;
    }
  }

  Future<void> _refreshServerCustomQueue() {
    final scope = _queueShuffleScope ?? 'library';
    final playlistId = _queueShufflePlaylistId;
    final artistId = _queueShuffleArtistId;
    final albumId = _queueShuffleAlbumId;
    final startTrackId = _host._playbackState.track?.id;

    return _host.queueShuffle(
      scope: scope,
      playlistId: playlistId,
      artistId: artistId,
      albumId: albumId,
      play: false,
      startTrackId: startTrackId,
    );
  }

  String _shuffleQueryMode(ShuffleMode mode) => switch (mode) {
    ShuffleMode.off => 'off',
    ShuffleMode.all => 'all',
    ShuffleMode.artist => 'artist',
    ShuffleMode.album => 'album',
    ShuffleMode.custom => 'custom',
    ShuffleMode.liked => 'liked',
    ShuffleMode.currentPlaylist => 'playlist',
  };

  List<Track> _shuffleTracks(List<Track> tracks, {String? avoidTrackId}) {
    final shuffled = List<Track>.from(tracks);

    shuffled.shuffle(_shuffleRandom);
    if (shuffled.isNotEmpty && shuffled.first.id == avoidTrackId) {
      final next = shuffled.indexWhere((track) => track.id != avoidTrackId);
      if (next > 0) {
        final first = shuffled[0];
        shuffled[0] = shuffled[next];
        shuffled[next] = first;
      }
    }

    return shuffled;
  }
}

String _newShuffleIdentifier() {
  final random = Random.secure();

  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
