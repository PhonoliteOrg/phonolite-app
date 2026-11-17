part of '../app_controller.dart';

/// Decides what a shuffle applies to and when choosing a track leaves it.
///
/// Resolves the artist, album or playlist for the current shuffle mode, and
/// decides whether a picked track falls outside liked or custom shuffle. The
/// coordinator keeps the shuffle state and the server deck.
extension _ShuffleContextResolution on _ShuffleCoordinator {
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
      final current = _host._playbackState.track;
      var albumId = current?.albumId ?? _host._lastAlbumId;

      if ((albumId == null || albumId.isEmpty) && current != null) {
        albumId = await _fetchShuffleAlbumId(current);
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
          albumId = await _fetchShuffleAlbumId(current);
        }

        if (albumId != null && albumId.isNotEmpty) {
          try {
            final album = await _host.connection.fetchAlbumById(albumId);

            artistId = album.artistId;
          } on Object catch (err) {
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

  /// The server's album id for [track]; null on failure, which callers handle with a fallback.
  Future<String?> _fetchShuffleAlbumId(Track track) async {
    try {
      return (await _host.connection.fetchTrackById(track.id)).albumId;
    } on Object catch (error) {
      _host._pushMessage('Shuffle track lookup failed: $error', level: LogLevel.debug);

      return null;
    }
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
    } on Object catch (err) {
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
      } on Object catch (err) {
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
            } on Object catch (error) {
              // A missing profile must not hide another contributor's genres.
              _host._pushMessage('Shuffle artist genre lookup failed for $artistId: $error', level: LogLevel.debug);
            }
          }
        }

        return true;
      } on Object catch (err) {
        _host._pushMessage('Failed to resolve custom shuffle match: $err');

        return true;
      }
    }

    return false;
  }
}
