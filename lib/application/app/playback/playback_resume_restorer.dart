part of '../app_controller.dart';

/// Resolves durable references against current collections before installing paused playback.
class _PlaybackResumeRestorer {
  final AppController _host;
  final _PlaybackResumeCoordinator _owner;
  bool _reconciling = false;

  _PlaybackResumeRestorer(this._host, this._owner);

  Future<void> restoreLocal(DevicePlaybackSnapshot snapshot, {required bool Function() isCurrent}) async {
    final saved = snapshot.checkpoint;
    if (saved == null) {
      if (isCurrent()) {
        _restoreModes(snapshot);
      }
      return;
    }

    final checkpoint = _withLocalMode(saved, snapshot.localShuffleMode);
    final rebuild = checkpoint.shuffleMode != saved.shuffleMode;

    final available = _localAvailable();
    var source = checkpoint.source;
    var members = await _localMembers(source, trackId: checkpoint.trackId);
    if (!isCurrent()) {
      return;
    }

    if (members == null) {
      source = PlaybackSourceContext(kind: 'standalone');
      members = [if (available[checkpoint.trackId] case final track?) track];
    }
    final eligible = {for (final track in members) _localId(track): track};
    final rebuilt = rebuild && checkpoint.shuffleMode != ShuffleMode.off
        ? _host._shuffleCoordinator._shuffleTracks(members)
        : members;
    final savedOrder = checkpoint.shuffleMode == ShuffleMode.off || rebuild
        ? rebuilt.map(_localId).toList()
        : snapshot.queueTrackIds;
    final queue = [
      for (final id in savedOrder)
        if (eligible[id] case final track?) track,
    ];
    final savedSet = savedOrder.toSet();
    if (checkpoint.shuffleMode == ShuffleMode.off || queue.isEmpty) {
      final additions = members.where((track) => !savedSet.contains(_localId(track))).toList();
      queue.addAll(
        checkpoint.shuffleMode == ShuffleMode.off ? additions : _host._shuffleCoordinator._shuffleTracks(additions),
      );
    }
    if (queue.isEmpty) {
      final mode = source.kind == 'standalone' ? ShuffleMode.off : checkpoint.shuffleMode;
      final context = mode == ShuffleMode.off ? source : checkpoint.shuffleContext;
      _owner._retainedLocalCheckpoint = checkpoint.copyWith(source: source, shuffleMode: mode, shuffleContext: context);
      _owner._localAuthority = true;
      _owner._source = source;
      _owner._shuffleContext = context;
      _owner._restoring = true;
      try {
        _restoreModes(snapshot);
        _restoreShuffleContext(context, mode, local: true);
        _restoreFilters(context, local: true);
        _host._updatePlayback(
          shuffleScope: ActionScope.local,
          shuffleMode: mode,
          queueSource: PlaybackQueueSource.offline,
          queueSourcePlaylistId: source.kind == 'playlist' ? source.id : null,
          localPlaybackSource: switch (source.kind) {
            'playlist' => LocalPlaybackSource.playlist,
            'liked' => LocalPlaybackSource.liked,
            _ => LocalPlaybackSource.library,
          },
          isLocalPlayback: true,
        );
      } finally {
        _owner._restoring = false;
      }
      return;
    }

    final current = queue.where((track) => _localId(track) == checkpoint.trackId).firstOrNull;
    final next = current ?? _nextSurvivor(savedOrder, checkpoint.cursor, eligible) ?? queue.first;
    final mode = source.kind == 'standalone' ? ShuffleMode.off : checkpoint.shuffleMode;
    _owner._restoring = true;
    try {
      _restoreModes(snapshot);
      _installQueue(queue, source, local: true, track: next, shuffleMode: mode);
      if (current != null &&
          checkpoint.cursor < savedOrder.length &&
          savedOrder[checkpoint.cursor] == checkpoint.trackId) {
        _host._playIndex = savedOrder.take(checkpoint.cursor).where(eligible.containsKey).length;
      }
      _owner._localAuthority = true;
      _owner._source = source;
      final context = mode == ShuffleMode.off ? source : checkpoint.shuffleContext;
      _owner._shuffleContext = context;
      _restoreShuffleContext(context, mode, local: true);
      _restoreFilters(context, local: true);
      final position = current == null ? 0 : snapshot.positionMs.clamp(0, next.durationMs).toInt();
      _host._updatePlayback(position: Duration(milliseconds: position));
    } finally {
      _owner._restoring = false;
    }
  }

  Future<void> restoreAccount(AccountPlaybackSnapshot snapshot, {required bool Function() isCurrent}) async {
    final checkpoint = snapshot.checkpoint;
    if (checkpoint == null) {
      return;
    }

    ServerShuffleDeck? deck;
    List<Track> tracks;
    Track? track;
    var source = checkpoint.source;
    final deckId = checkpoint.deckId;
    if (checkpoint.shuffleMode != ShuffleMode.off && deckId != null) {
      final offset = (checkpoint.cursor ~/ ServerShuffleDeck.pageSize) * ServerShuffleDeck.pageSize;
      final first = await _host.connection.fetchAccountPlaybackDeck(deckId, offset: offset);
      if (!isCurrent()) {
        return;
      }

      deck = ServerShuffleDeck(
        first,
        load: (offset) => _host.connection.fetchAccountPlaybackDeck(deckId, offset: offset),
      );
      if (!await deck.restorePosition(checkpoint.cursor) || !isCurrent()) {
        deck.close();
        return;
      }
      tracks = deck.tracks;
      track = tracks[deck.queueIndex];
    } else {
      final selection = await _serverSelection(source, checkpoint.trackId);
      source = selection.source;
      tracks = selection.tracks;
      if (!isCurrent() || tracks.isEmpty) {
        return;
      }

      track = tracks.where((item) => item.id == checkpoint.trackId).firstOrNull ?? tracks.first;
    }

    _owner._restoring = true;
    try {
      _host._shuffleCoordinator._clearServerShuffleSession();
      if (deck != null) {
        _host._shuffleCoordinator._serverDeck = deck;
        _host._shuffleCoordinator._serverDeckSessionRevision = _host.connection.sessionRevision;
        _host._shuffleCoordinator._serverDeckReady = true;
      }
      _installQueue(tracks, source, local: false, track: track, shuffleMode: checkpoint.shuffleMode, deck: deck);
      _owner._localAuthority = false;
      _owner._source = source;
      _owner._shuffleContext = checkpoint.shuffleMode == ShuffleMode.off ? source : checkpoint.shuffleContext;
      _owner._ownsAccountGeneration = snapshot.generation != null;
      _owner._activeDurableDeckId = checkpoint.deckId;
      _restoreShuffleContext(checkpoint.shuffleContext, checkpoint.shuffleMode, local: false);
      _restoreFilters(checkpoint.shuffleContext, local: false);
    } finally {
      _owner._restoring = false;
    }
  }

  Future<void> reconcileLocal() async {
    if (_reconciling || _owner._closed || _host._playbackState.track == null) {
      return;
    }

    _reconciling = true;
    final selection = _owner._selection;
    try {
      final members = await _localMembers(_owner._source, trackId: _localId(_host._playbackState.track!));
      if (_owner._closed || selection != _owner._selection || !_owner._localAuthority) {
        return;
      }

      final current = _host._playbackState.track!;
      if (members == null) {
        _host._gaplessCoordinator.invalidate(prepareAgain: true);
        _owner._source = PlaybackSourceContext(kind: 'standalone');
        _host._playQueue = _localAvailable().containsKey(_localId(current)) ? [current] : [];
        _host._playIndex = 0;
        _host._updatePlayback(
          shuffleMode: ShuffleMode.off,
          queueSourcePlaylistId: null,
          localPlaybackSource: LocalPlaybackSource.library,
        );
      } else {
        final eligible = members.map(_localId).toSet();
        final oldIndex = _host._playIndex;
        final oldQueue = _host._playQueue;
        final removedBefore = oldQueue
            .take(max(0, oldIndex))
            .where((track) => !eligible.contains(_localId(track)))
            .length;
        final nextQueue = oldQueue.where((track) => eligible.contains(_localId(track))).toList();
        if (nextQueue.length != oldQueue.length) _host._gaplessCoordinator.invalidate(prepareAgain: true);
        _host._playQueue = nextQueue;
        final currentIndex = _host._playQueue.indexWhere((track) => _localId(track) == _localId(current));
        _host._playIndex = currentIndex >= 0 ? currentIndex : max(-1, oldIndex - removedBefore - 1);
      }
      _owner.changed();
    } catch (error) {
      AppLogger.debug('Local playback reconciliation deferred: $error');
    } finally {
      _reconciling = false;
    }
  }

  String _localId(Track track) => track.localId ?? track.id;

  PlaybackResumeCheckpoint _withLocalMode(PlaybackResumeCheckpoint checkpoint, ShuffleMode mode) {
    if (mode == checkpoint.shuffleMode) {
      return checkpoint;
    }

    final context = switch (mode) {
      ShuffleMode.off => checkpoint.source,
      ShuffleMode.all => PlaybackSourceContext(kind: 'library'),
      ShuffleMode.liked => PlaybackSourceContext(kind: 'liked'),
      ShuffleMode.album => _localAlbumContext(checkpoint.trackId) ?? checkpoint.source,
      ShuffleMode.artist => _localArtistContext(checkpoint.trackId) ?? checkpoint.source,
      ShuffleMode.currentPlaylist =>
        checkpoint.source.kind == 'playlist' ? checkpoint.source : checkpoint.shuffleContext,
      ShuffleMode.custom => PlaybackSourceContext(
        kind: 'custom',
        artistIds: _host._customShuffleSettings.localArtistIds,
        genres: _host._customShuffleSettings.localGenres,
      ),
    };
    final valid = switch (mode) {
      ShuffleMode.album => context.kind == 'album',
      ShuffleMode.artist => context.kind == 'artist',
      ShuffleMode.currentPlaylist => context.kind == 'playlist',
      _ => true,
    };
    final effective = valid ? mode : ShuffleMode.off;
    return checkpoint.copyWith(
      source: effective == ShuffleMode.off ? checkpoint.source : context,
      shuffleMode: effective,
      shuffleContext: effective == ShuffleMode.off ? checkpoint.source : context,
      cursor: 0,
    );
  }

  PlaybackSourceContext? _localAlbumContext(String trackId) {
    final album = _host._localLibrary.albumForTrackId(trackId);
    return album == null ? null : PlaybackSourceContext(kind: 'album', id: album.id);
  }

  PlaybackSourceContext? _localArtistContext(String trackId) {
    final artist = _host._localLibrary.artistForTrackId(trackId);
    return artist == null ? null : PlaybackSourceContext(kind: 'artist', id: artist.id);
  }

  Map<String, Track> _localAvailable() => {
    for (final track in _host.offlineTracks)
      if (_localFileExists(track)) _localId(track): track,
  };

  bool _localFileExists(Track track) {
    final path = _host.availableOfflineDownloadForTrack(_localId(track))?.filePath;
    return path != null && File(path).existsSync();
  }

  Future<List<Track>?> _localMembers(PlaybackSourceContext source, {String? trackId}) async {
    final available = _localAvailable();
    List<Track>? tracks;
    switch (source.kind) {
      case 'standalone':
        tracks = [if (available[trackId] case final track?) track];
      case 'playlist':
        await _host.loadLocalPlaylists();
        if (!_host.localPlaylists.any((playlist) => playlist.id == source.id)) {
          return null;
        }

        await _host.loadLocalPlaylistTracks(source.id!);
        tracks = _host.localPlaylistTracks;
      case 'liked':
        await _host.loadLocalLikedTracks();
        tracks = _host.localLiked;
      case 'album':
        tracks = _host._localLibrary.album(source.id!)?.tracks;
      case 'artist':
        tracks = _host._localLibrary.artist(source.id!)?.tracksForArtist;
      case 'custom':
        tracks = available.values
            .where(
              (track) => _host._localLibrary.matchesCustomShuffle(
                track,
                artistIds: source.artistIds.toSet(),
                genres: source.genres.toSet(),
              ),
            )
            .toList();
      default:
        tracks = available.values.toList();
    }
    return tracks?.where((track) => available.containsKey(_localId(track))).toList();
  }

  Future<void> restoreCachedAccount(AccountPlaybackSnapshot snapshot, {required bool Function() isCurrent}) async {
    final checkpoint = snapshot.checkpoint;
    if (checkpoint == null || !isCurrent()) {
      return;
    }

    final origin = ServerTrust.origin(Uri.parse(_host.connection.baseUrl));
    final download = _host.availableOfflineDownloads
        .where(
          (download) =>
              ServerTrust.origin(Uri.parse(download.serverBaseUrl)) == origin &&
              (download.track.serverTrackId ?? download.track.id) == checkpoint.trackId &&
              download.filePath != null &&
              File(download.filePath!).existsSync(),
        )
        .firstOrNull;
    if (download == null) {
      return;
    }

    final track = download.track.copyWith(id: checkpoint.trackId, serverTrackId: checkpoint.trackId);
    _owner._restoring = true;
    try {
      _installQueue([track], checkpoint.source, local: false, track: track, shuffleMode: checkpoint.shuffleMode);
      _owner._source = checkpoint.source;
      _owner._shuffleContext = checkpoint.shuffleContext;
      _owner._localAuthority = false;
      _owner._deferredAccountDeck = checkpoint;
      _owner._activeDurableDeckId = checkpoint.deckId;
      _restoreShuffleContext(checkpoint.shuffleContext, checkpoint.shuffleMode, local: false);
      _restoreFilters(checkpoint.shuffleContext, local: false);
    } finally {
      _owner._restoring = false;
    }
  }

  Future<void> restoreDeferredDeck() async {
    final checkpoint = _owner._deferredAccountDeck;
    final deckId = checkpoint?.deckId;
    final current = _host._playbackState.track;
    if (checkpoint == null || deckId == null || current == null) {
      return;
    }

    final session = _host.connection.sessionRevision;
    final selection = _owner._selection;
    final request = _host._shuffleCoordinator._serverShuffleRequests.current;
    bool isCurrent() =>
        !_owner._closed &&
        _owner._selection == selection &&
        _host._sessionCoordinator._isServerSessionCurrent(session) &&
        identical(_owner._deferredAccountDeck, checkpoint) &&
        _host._shuffleCoordinator._serverShuffleRequests.isCurrent(request) &&
        _host._playbackState.serverShuffleMode == checkpoint.shuffleMode;

    var sourceChecked = false;
    try {
      await _validateServerSource(checkpoint.source);
      if (!isCurrent()) {
        return;
      }
      sourceChecked = true;
      final offset = (checkpoint.cursor ~/ ServerShuffleDeck.pageSize) * ServerShuffleDeck.pageSize;
      final first = await _host.connection.fetchAccountPlaybackDeck(deckId, offset: offset);
      if (!isCurrent()) {
        return;
      }

      final deck = ServerShuffleDeck(
        first,
        load: (offset) => _host.connection.fetchAccountPlaybackDeck(deckId, offset: offset),
      );
      if (!await deck.restorePosition(checkpoint.cursor) || !isCurrent()) {
        deck.close();
        return;
      }
      if (deck.tracks[deck.queueIndex].id != (current.serverTrackId ?? current.id)) {
        deck.retainExternalCurrent();
      }

      final shuffle = _host._shuffleCoordinator;
      shuffle._serverDeck = deck;
      shuffle._serverDeckSessionRevision = session;
      shuffle._serverDeckReady = true;
      shuffle._applyServerShuffleWindow(deck);
      _owner._deferredAccountDeck = null;
    } on ApiException catch (error) {
      if (error.statusCode == 404 && isCurrent()) {
        _owner._deferredAccountDeck = null;
        if (!sourceChecked) {
          _detachServerSource(current);
        }
      } else {
        rethrow;
      }
    }
  }

  Future<bool> restoreDeferredNavigation(int direction) async {
    final checkpoint = _owner._deferredAccountDeck;
    final current = _host._playbackState.track;
    if (checkpoint == null || current == null) {
      return true;
    }

    if (checkpoint.shuffleMode != ShuffleMode.off) {
      final selection = _owner._selection;
      final session = _host.connection.sessionRevision;
      await restoreDeferredDeck();
      if (_owner._closed ||
          _owner._selection != selection ||
          !_host._sessionCoordinator._isServerSessionCurrent(session)) {
        return false;
      }
      return _owner._source.kind != 'standalone' || checkpoint.source.kind == 'standalone';
    }

    final session = _host.connection.sessionRevision;
    final selection = _owner._selection;
    bool isCurrent() =>
        !_owner._closed &&
        _owner._selection == selection &&
        identical(_owner._deferredAccountDeck, checkpoint) &&
        _host._sessionCoordinator._isServerSessionCurrent(session);

    try {
      if (!_isBroadServerSource(checkpoint.source)) {
        await _validateServerSource(checkpoint.source);
      }
      final selection = await _serverSelection(checkpoint.source, checkpoint.trackId);
      final tracks = selection.tracks;
      if (!isCurrent()) {
        return false;
      }

      final source = selection.source;
      _host._setQueue(
        tracks,
        startTrackId: current.id,
        queueSource: switch (source.kind) {
          'playlist' => PlaybackQueueSource.playlist,
          'liked' => PlaybackQueueSource.liked,
          _ => PlaybackQueueSource.none,
        },
        queueSourcePlaylistId: source.kind == 'playlist' ? source.id : null,
        sourceContext: source,
      );
      if (tracks.isEmpty) {
        return false;
      }

      final index = tracks.indexWhere((track) => track.id == (current.serverTrackId ?? current.id));
      _host._playIndex = index >= 0
          ? index
          : direction > 0
          ? -1
          : 0;
      _owner._deferredAccountDeck = null;
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 404 && isCurrent()) {
        _owner._deferredAccountDeck = null;
        _detachServerSource(current);
        return false;
      }
      rethrow;
    }
  }

  Future<void> _validateServerSource(PlaybackSourceContext source) async {
    switch (source.kind) {
      case 'playlist':
        await _host.connection.fetchPlaylistTracks(source.id!);
      case 'album':
        await _host.connection.fetchTracks(source.id!);
      case 'artist':
        await _host.connection.fetchArtistById(source.id!);
    }
  }

  Future<bool> normalizeServerQueue({required bool Function() isCurrent}) async {
    final current = _host._playbackState.track;
    if (current == null || !_isBroadServerSource(_owner._source)) {
      return true;
    }

    final selection = await _serverSelection(_owner._source, current.serverTrackId ?? current.id);
    if (!isCurrent()) {
      return false;
    }

    _host._setQueue(
      selection.tracks,
      startTrackId: current.id,
      queueSource: PlaybackQueueSource.none,
      sourceContext: selection.source,
    );
    _owner._shuffleContext = selection.source;
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    return true;
  }

  bool _isBroadServerSource(PlaybackSourceContext source) => {'library', 'artist', 'custom'}.contains(source.kind);

  Future<({PlaybackSourceContext source, List<Track> tracks})> _serverSelection(
    PlaybackSourceContext source,
    String trackId,
  ) async {
    if (!_isBroadServerSource(source)) {
      return (source: source, tracks: await _serverMembers(source, trackId));
    }

    final track = await _host.connection.fetchTrackById(trackId);
    final albumId = track.albumId;
    if (albumId != null && albumId.isNotEmpty) {
      try {
        final tracks = await _host.connection.fetchTracks(albumId);
        if (tracks.isNotEmpty) {
          return (source: PlaybackSourceContext(kind: 'album', id: albumId), tracks: tracks);
        }
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }
      }
    }
    return (source: PlaybackSourceContext(kind: 'standalone'), tracks: [track]);
  }

  void _detachServerSource(Track current) {
    final source = PlaybackSourceContext(kind: 'standalone');
    _host._setQueue([current], queueSource: PlaybackQueueSource.none, sourceContext: source);
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    _owner._shuffleContext = source;
    _host._updatePlayback(shuffleScope: ActionScope.server, shuffleMode: ShuffleMode.off);
  }

  Future<List<Track>> _serverMembers(PlaybackSourceContext source, String trackId) async {
    return switch (source.kind) {
      'playlist' => _host.connection.fetchPlaylistTracks(source.id!),
      'liked' => _host.connection.fetchLikedTracks(),
      'album' => _host.connection.fetchTracks(source.id!),
      _ => [await _host.connection.fetchTrackById(trackId)],
    };
  }

  Track? _nextSurvivor(List<String> order, int cursor, Map<String, Track> available) {
    for (final id in order.skip(max(0, cursor))) {
      if (available[id] case final track?) {
        return track;
      }
    }
    return null;
  }

  void _restoreModes(DevicePlaybackSnapshot snapshot) {
    _host._updatePlayback(shuffleScope: ActionScope.local, shuffleMode: snapshot.localShuffleMode, nowPlaying: false);
    _host._updatePlayback(shuffleScope: ActionScope.server, shuffleMode: snapshot.serverShuffleMode, nowPlaying: false);
    _host._updatePlayback(shuffleScope: snapshot.shuffleScope, nowPlaying: false);
  }

  void _installQueue(
    List<Track> tracks,
    PlaybackSourceContext source, {
    required bool local,
    required Track track,
    required ShuffleMode shuffleMode,
    ServerShuffleDeck? deck,
  }) {
    final queueSource = local
        ? PlaybackQueueSource.offline
        : switch (source.kind) {
            'playlist' => PlaybackQueueSource.playlist,
            'liked' => PlaybackQueueSource.liked,
            _ => PlaybackQueueSource.none,
          };
    final offlineSource = switch (source.kind) {
      'playlist' => OfflineQueueSource.localPlaylist,
      'liked' => OfflineQueueSource.localLiked,
      _ => OfflineQueueSource.tracks,
    };
    _host._setQueue(
      tracks,
      startTrackId: track.id,
      queueSource: queueSource,
      queueSourcePlaylistId: source.kind == 'playlist' ? source.id : null,
      offlineQueueSource: local ? offlineSource : OfflineQueueSource.none,
      preserveServerShuffle: deck != null,
      sourceContext: source,
    );
    if (deck != null) {
      _host._shuffleCoordinator._applyServerShuffleWindow(deck);
    }

    _host._wantsPlayback = false;
    _host._updatePlayback(
      track: track,
      isPlaying: false,
      isLoading: false,
      isLocalPlayback: local,
      shuffleScope: local ? ActionScope.local : ActionScope.server,
      shuffleMode: shuffleMode,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      bufferRatio: 0,
    );
  }

  void _restoreShuffleContext(PlaybackSourceContext context, ShuffleMode mode, {required bool local}) {
    final shuffle = _host._shuffleCoordinator;
    shuffle._queueShuffleMode = mode;
    shuffle._queueShuffleScope = local
        ? switch (context.kind) {
            'playlist' => 'localPlaylist',
            'liked' => 'localLiked',
            'artist' => 'localArtist',
            'album' => 'localAlbum',
            'custom' => 'localCustom',
            _ => 'localLibrary',
          }
        : switch (context.kind) {
            'playlist' => 'playlist',
            'liked' => 'liked',
            _ => 'library',
          };
    shuffle._queueShufflePlaylistId = context.kind == 'playlist' ? context.id : null;
    shuffle._queueShuffleArtistId = context.kind == 'artist' ? context.id : null;
    shuffle._queueShuffleAlbumId = context.kind == 'album' ? context.id : null;
  }

  void _restoreFilters(PlaybackSourceContext context, {required bool local}) {
    if (context.kind != 'custom') {
      return;
    }

    final preferences = _host._preferencesCoordinator;
    preferences._customShuffleSettings = preferences._customShuffleSettings.copyWith(
      artistIds: local ? null : context.artistIds,
      genres: local ? null : context.genres,
      localArtistIds: local ? context.artistIds : null,
      localGenres: local ? context.genres : null,
    );
    preferences._customShuffleSettingsController.add(preferences._customShuffleSettings);
  }
}
