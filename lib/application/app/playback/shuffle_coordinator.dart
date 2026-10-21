part of 'package:phonolite_app/application/app/app_controller.dart';

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
  }) async {
    if (!_host._requireServer('starting server shuffle')) {
      return;
    }

    try {
      if (_host._playbackState.shuffleMode == ShuffleMode.off) {
        _host._pushMessage('Shuffle is off');

        return;
      }

      if (_host._playbackState.shuffleScope != ActionScope.server) {
        _host._pushMessage('Server shuffle requires a server playback scope');

        return;
      }

      final queueSource = queueSourceOverride ?? _serverShuffleQueueSource(scope);
      final queueSourcePlaylistId = queueSource == PlaybackQueueSource.playlist
          ? (queueSourcePlaylistIdOverride ?? playlistId)
          : null;

      if (scope == 'playlist') {
        if (playlistId == null) {
          _host._pushMessage('No playlist selected for shuffle');

          return;
        }

        final tracks = await _host.connection.fetchPlaylistTracks(playlistId);

        if (tracks.isEmpty) {
          _host._pushMessage('No tracks found for playlist');

          return;
        }

        _rememberShuffleContext(scope: scope, playlistId: playlistId, artistId: artistId, albumId: albumId);

        final normalized = _host._normalizeQueueTracks(_shuffleTracks(tracks));

        _host._setQueue(
          normalized,
          startTrackId: startTrackId,
          queueSource: queueSource,
          queueSourcePlaylistId: queueSourcePlaylistId,
        );
        _host._armAutoAdvanceGuard();

        if (play) {
          await _host._playCurrent();
        }

        return;
      }

      if (scope == 'liked') {
        final tracks = await _host.connection.fetchLikedTracks();

        if (tracks.isEmpty) {
          _host._pushMessage('No liked tracks found');

          return;
        }

        _rememberShuffleContext(scope: scope, playlistId: playlistId, artistId: artistId, albumId: albumId);

        final normalized = _host._normalizeQueueTracks(_shuffleTracks(tracks));

        _host._setQueue(
          normalized,
          startTrackId: startTrackId,
          queueSource: queueSource,
          queueSourcePlaylistId: queueSourcePlaylistId,
        );
        _host._armAutoAdvanceGuard();

        if (play) {
          await _host._playCurrent();
        }

        return;
      }

      if (_host._playbackState.shuffleMode == ShuffleMode.artist && artistId == null) {
        _host._pushMessage('Select an artist to shuffle');

        return;
      }

      if (_host._playbackState.shuffleMode == ShuffleMode.album && albumId == null) {
        _host._pushMessage('Select an album to shuffle');

        return;
      }

      final mode = _shuffleQueryMode(_host._playbackState.shuffleMode);
      final isCustom = _host._playbackState.shuffleMode == ShuffleMode.custom;

      if (isCustom) {
        await _host._ensureCustomShuffleSettingsLoaded();
      }

      final customArtistIds = isCustom ? _host._customShuffleSettings.artistIds : null;
      final customGenres = isCustom ? _host._customShuffleSettings.genres : null;

      if (isCustom &&
          (customArtistIds == null || customArtistIds.isEmpty) &&
          (customGenres == null || customGenres.isEmpty)) {
        _host._pushMessage('Custom shuffle has no filters; using full library.');
      }

      final tracks = await _host.connection.fetchShuffleTracks(
        mode: mode,
        artistId: artistId,
        albumId: albumId,
        artistIds: customArtistIds,
        genres: customGenres,
      );

      if (tracks.isEmpty) {
        _host._pushMessage('No tracks found for shuffle');

        return;
      }

      _rememberShuffleContext(scope: scope, playlistId: playlistId, artistId: artistId, albumId: albumId);
      _host._setQueue(
        _shuffleTracks(tracks),
        startTrackId: startTrackId,
        queueSource: queueSource,
        queueSourcePlaylistId: queueSourcePlaylistId,
      );
      _host._armAutoAdvanceGuard();

      if (play) {
        await _host._playCurrent();
      }
    } on ApiException catch (err) {
      _host._handleApiError(err, context: 'queue shuffle');
    } catch (err) {
      _host._pushMessage('Failed to queue shuffle: $err');
    }
  }

  Future<void> queueLocalShuffle({
    String? playlistId,
    String? artistId,
    String? albumId,
    bool play = true,
    String? startTrackId,
  }) async {
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
        tracks = _host.localPlaylistTracks;
        offlineSource = OfflineQueueSource.localPlaylist;
        contextScope = 'localPlaylist';
      } else if (mode == ShuffleMode.liked) {
        if (_host.localLiked.isEmpty) {
          await _host.loadLocalLikedTracks();
        }

        tracks = _host.localLiked;
        offlineSource = OfflineQueueSource.localLiked;
        contextScope = 'localLiked';
      } else if (mode == ShuffleMode.artist) {
        contextArtistId = _resolveLocalShuffleArtistId(startTrackId: startTrackId, artistId: artistId);

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
        contextAlbumId = _resolveLocalShuffleAlbumId(startTrackId: startTrackId, albumId: albumId);

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
        _shuffleTracks(tracks),
        startTrackId: startTrackId,
        queueSource: PlaybackQueueSource.offline,
        queueSourcePlaylistId: sourcePlaylistId,
        offlineQueueSource: offlineSource,
      );
      _host._armAutoAdvanceGuard();

      if (play) {
        await _host._playCurrent();
      }
    } catch (err) {
      _host._pushMessage('Failed to queue local shuffle: $err');
    }
  }

  PlaybackQueueSource _serverShuffleQueueSource(String scope) {
    if (scope == 'playlist') {
      return PlaybackQueueSource.playlist;
    }

    if (scope == 'liked') {
      return PlaybackQueueSource.liked;
    }

    if (_host._playbackState.shuffleMode == ShuffleMode.liked) {
      return PlaybackQueueSource.liked;
    }

    return PlaybackQueueSource.none;
  }

  String? _resolveLocalShuffleArtistId({String? startTrackId, String? artistId}) {
    final fromStart = _localLibrary.artistForTrackId(startTrackId)?.id;

    if (fromStart != null && fromStart.isNotEmpty) {
      return fromStart;
    }

    final current = _host._playbackState.track;

    if (current != null) {
      final fromCurrent = _localLibrary.artistForTrack(current)?.id;

      if (fromCurrent != null && fromCurrent.isNotEmpty) {
        return fromCurrent;
      }
    }

    final explicit = artistId?.trim();

    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    if (_queueShuffleScope == 'localArtist' && _queueShuffleArtistId != null && _queueShuffleArtistId!.isNotEmpty) {
      return _queueShuffleArtistId;
    }

    return null;
  }

  String? _resolveLocalShuffleAlbumId({String? startTrackId, String? albumId}) {
    final fromStart = _localLibrary.albumForTrackId(startTrackId)?.id;

    if (fromStart != null && fromStart.isNotEmpty) {
      return fromStart;
    }

    final current = _host._playbackState.track;

    if (current != null) {
      final fromCurrent = _localLibrary.albumForTrack(current)?.id;

      if (fromCurrent != null && fromCurrent.isNotEmpty) {
        return fromCurrent;
      }
    }

    final explicit = albumId?.trim();

    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    if (_queueShuffleScope == 'localAlbum' && _queueShuffleAlbumId != null && _queueShuffleAlbumId!.isNotEmpty) {
      return _queueShuffleAlbumId;
    }

    return null;
  }

  void _rememberShuffleContext({required String scope, String? playlistId, String? artistId, String? albumId}) {
    _queueShuffleMode = _host._playbackState.shuffleMode;
    _queueShuffleScope = scope;
    _queueShufflePlaylistId = playlistId;
    _queueShuffleArtistId = artistId;
    _queueShuffleAlbumId = albumId;
  }

  Future<ShuffleContext?> _resolveShuffleContext() async {
    if (_queueShuffleScope != null &&
        _queueShuffleScope!.isNotEmpty &&
        _queueShuffleMode == _host._playbackState.shuffleMode) {
      return ShuffleContext(
        scope: _queueShuffleScope!,
        playlistId: _queueShufflePlaylistId,
        artistId: _queueShuffleArtistId,
        albumId: _queueShuffleAlbumId,
      );
    }

    if (_host._playbackState.shuffleMode == ShuffleMode.album) {
      var albumId = _host._playbackState.track?.albumId ?? _host._lastAlbumId;

      if (albumId == null || albumId.isEmpty) {
        final current = _host._playbackState.track;

        if (current != null) {
          try {
            final full = await _host.connection.fetchTrackById(current.id);

            albumId = full.albumId;
          } catch (_) {}
        }
      }

      if (albumId == null || albumId.isEmpty) {
        _host._pushMessage('Shuffle album will apply after a track starts.');

        return null;
      }

      return ShuffleContext(scope: 'library', albumId: albumId);
    }

    if (_host._playbackState.shuffleMode == ShuffleMode.artist) {
      String? artistId;
      final current = _host._playbackState.track;

      if (current != null) {
        var albumId = current.albumId;

        if (albumId == null || albumId.isEmpty) {
          try {
            final full = await _host.connection.fetchTrackById(current.id);

            albumId = full.albumId;
          } catch (_) {}
        }

        if (albumId != null && albumId.isNotEmpty) {
          try {
            final album = await _host.connection.fetchAlbumById(albumId);

            artistId = album.artistId;
          } catch (err) {
            _host._pushMessage('Failed to resolve artist for shuffle: $err');
          }
        }
      }

      artistId ??= _host._lastArtistId;

      if (artistId == null || artistId.isEmpty) {
        _host._pushMessage('Shuffle artist will apply after a track starts.');

        return null;
      }

      return ShuffleContext(scope: 'library', artistId: artistId);
    }

    if (_host._playbackState.shuffleMode == ShuffleMode.currentPlaylist) {
      final playlistId = _host._playbackState.queueSource == PlaybackQueueSource.playlist
          ? _host._playbackState.queueSourcePlaylistId
          : null;

      if (playlistId == null || playlistId.isEmpty) {
        _host._pushMessage('Shuffle current playlist requires a playlist source.');

        return null;
      }

      return ShuffleContext(scope: 'playlist', playlistId: playlistId);
    }

    return const ShuffleContext(scope: 'library');
  }

  Future<bool> _ensureShuffleQueue({bool play = true}) async {
    if (_host._playbackState.shuffleScope == ActionScope.local) {
      return _ensureLocalShuffleQueue(play: play);
    }

    return _ensureServerShuffleQueue(play: play);
  }

  Future<bool> _ensureServerShuffleQueue({bool play = true}) async {
    if (_host._playbackState.shuffleMode == ShuffleMode.off) {
      return false;
    }

    if (_host._playQueue.isNotEmpty &&
        _queueShuffleMode == _host._playbackState.shuffleMode &&
        _queueShuffleScope != null) {
      if (play && _host._playbackState.track == null) {
        _host._playIndex = _host._playIndex.clamp(0, _host._playQueue.length - 1);
        await _host._playCurrent();
      }

      return true;
    }

    final context = await _resolveShuffleContext();
    if (context == null) {
      return false;
    }

    final startTrackId = play ? null : _host._playbackState.track?.id;

    await _host.queueShuffle(
      scope: context.scope,
      playlistId: context.playlistId,
      artistId: context.artistId,
      albumId: context.albumId,
      play: play,
      startTrackId: startTrackId,
    );

    return _host._playQueue.isNotEmpty;
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
      } catch (err) {
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

    _host._setQueue(tracks, startTrackId: current.id, queueSource: PlaybackQueueSource.none);
    _queueShuffleMode = ShuffleMode.off;
    _queueShuffleScope = null;

    return true;
  }

  Future<({String? artistId, String? albumId})> _resolveAlbumArtistForTrack(String trackId) async {
    String? albumId;
    String? artistId;

    try {
      final full = await _host.connection.fetchTrackById(trackId);

      albumId = full.albumId;

      if (albumId != null && albumId.isNotEmpty) {
        final album = await _host.connection.fetchAlbumById(albumId);

        artistId = album.artistId;
      }
    } catch (err) {
      _host._pushMessage('Failed to resolve shuffle context: $err');
    }

    return (artistId: artistId, albumId: albumId);
  }

  Future<void> _maybeDisableShuffleForTrackSelection(String trackId) async {
    if (_host._playbackState.shuffleScope != ActionScope.server) {
      return;
    }

    final mode = _host._playbackState.shuffleMode;

    if (mode != ShuffleMode.liked && mode != ShuffleMode.custom) {
      return;
    }

    final shouldDisable = await _shouldDisableShuffleForTrackSelection(trackId, mode);

    if (shouldDisable) {
      _host.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    }
  }

  Future<bool> _shouldDisableShuffleForTrackSelection(String trackId, ShuffleMode mode) async {
    if (mode == ShuffleMode.liked) {
      final isLiked = _host._liked.any((track) => track.id == trackId);

      if (isLiked) {
        return false;
      }

      if (_host._liked.isNotEmpty) {
        return true;
      }

      try {
        final full = await _host.connection.fetchTrackById(trackId);

        return !full.liked;
      } catch (err) {
        _host._pushMessage('Failed to confirm liked status: $err');

        return true;
      }
    }

    if (mode == ShuffleMode.custom) {
      try {
        await _host._ensureCustomShuffleSettingsLoaded();

        final customArtists = _host._customShuffleSettings.artistIds;
        final customGenres = _host._customShuffleSettings.genres;

        if (customArtists.isEmpty && customGenres.isEmpty) {
          return false;
        }

        final track = await _host.connection.fetchTrackById(trackId);
        final artistIds = <String>{
          for (final credit in track.credits)
            if (credit.isPerformingArtist && credit.artistId.trim().isNotEmpty) credit.artistId.trim(),
          if (track.artistId?.trim().isNotEmpty ?? false) track.artistId!.trim(),
        };

        if (artistIds.any(customArtists.contains)) {
          return false;
        }

        final genreFilter = customGenres.map((genre) => genre.trim().toLowerCase()).toSet();

        bool matchesGenre(Iterable<String> genres) =>
            genres.any((genre) => genreFilter.contains(genre.trim().toLowerCase()));

        if (genreFilter.isNotEmpty && matchesGenre(track.genres)) {
          return false;
        }

        final albumId = track.albumId;
        final album = albumId?.trim().isNotEmpty == true ? await _host.connection.fetchAlbumById(albumId!) : null;

        artistIds.addAll([
          if (album?.artistId.trim().isNotEmpty ?? false) album!.artistId.trim(),
          for (final credit in album?.credits ?? const <ArtistCredit>[])
            if (credit.isAlbumArtist && credit.artistId.trim().isNotEmpty) credit.artistId.trim(),
        ]);

        if (artistIds.any(customArtists.contains)) {
          return false;
        }

        if (genreFilter.isNotEmpty) {
          if (matchesGenre(album?.genres ?? const <String>[])) {
            return false;
          }

          for (final artistId in artistIds) {
            try {
              final cached = [
                ..._host._artists,
                ...track.offlineArtists,
                if (track.offlineArtist != null) track.offlineArtist!,
              ].where((artist) => artist.id == artistId).firstOrNull;
              final artist = cached ?? await _host.connection.fetchArtistById(artistId);

              if (artist.id == artistId && matchesGenre(artist.genres)) {
                return false;
              }
            } catch (_) {
              // A missing profile must not hide another contributor's genres.
            }
          }
        }

        return true;
      } catch (err) {
        _host._pushMessage('Failed to resolve custom shuffle match: $err');

        return true;
      }
    }

    return false;
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

  String _shuffleQueryMode(ShuffleMode mode) {
    switch (mode) {
      case ShuffleMode.off:
        return 'off';
      case ShuffleMode.all:
        return 'all';
      case ShuffleMode.artist:
        return 'artist';
      case ShuffleMode.album:
        return 'album';
      case ShuffleMode.custom:
        return 'custom';
      case ShuffleMode.liked:
        return 'liked';
      case ShuffleMode.currentPlaylist:
        return 'playlist';
    }
  }

  List<Track> _shuffleTracks(List<Track> tracks) {
    final shuffled = List<Track>.from(tracks);

    shuffled.shuffle(_shuffleRandom);

    return shuffled;
  }
}

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
