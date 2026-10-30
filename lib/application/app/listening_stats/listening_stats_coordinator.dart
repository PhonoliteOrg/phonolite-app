part of '../app_controller.dart';

class _ListeningStatsCoordinator {
  final AppController _host;
  AudioEngine? _audio;
  ListeningStatsSync? _listeningSync;
  StreamSubscription<ListeningStatsSnapshot>? _listeningSubscription;
  final _statsRefreshDebounce = DebouncedAction();
  Future<void>? _statsGenreRepair;
  ({String scope, int generation, int revision})? _statsGenreRepairCursorKey;
  String? _statsGenreRepairAfterTrackId;
  final _statsCollectionController = StreamController<bool>.broadcast();
  Map<String, dynamic>? _listeningSessionContext;
  bool _listeningClosed = false;
  String? _statsServerId;
  String? _statsUserId;
  final _statsReads = RequestGeneration();
  bool _resettingListeningStats = false;
  bool _suspendedListeningForReset = false;
  final _statsController = StreamController<StatsResponse?>.broadcast();
  StatsResponse? _stats;

  _ListeningStatsCoordinator(this._host);

  Stream<bool> get statsCollectionEnabledStream => _statsCollectionController.stream;

  bool get statsSyncing => _listeningSync?.syncing ?? false;

  String? get statsSyncMessage => _host._listeningStats.storageError != null
      ? 'Listening history could not be saved on this device.'
      : _listeningSync?.message;

  bool get statsServerCollectionEnabled => _listeningSync?.serverCollectionEnabled ?? false;

  bool get canImportLocalStats =>
      !_resettingListeningStats && _host._listeningStats.canImportLocalHistory && _host.statsCollectionEnabled;

  Stream<StatsResponse?> get statsStream => _statsController.stream;

  StatsResponse? get stats => _stats;

  Future<void> setStatsCollectionEnabled(bool value) async {
    if (_host._disposed || value == _host.statsCollectionEnabled) {
      return;
    }

    _host._gaplessCoordinator.invalidate();

    // Disable the worker immediately, before any disk or network operation.
    if (!value) {
      _audio?.configureListening(null);
    }

    _listeningSessionContext = null;

    try {
      await _host._listeningStats.setEnabled(value);

      if (_host._disposed) {
        return;
      }

      final track = _host._playbackState.track;

      if (value && track != null) {
        _prepareListeningSession(track, newSession: true, updateActive: true);
      }

      _statsCollectionController.add(_host.statsCollectionEnabled);

      final sync = _listeningSync;

      if (sync != null) {
        // Saving this setting never waits for a poor server connection.
        // Immediate sync also queues preference delivery after an in-flight batch.
        unawaited(sync.sync(immediate: true));
      }

      await _refreshLocalStats();
      _host._gaplessCoordinator.prepare();
    } catch (error) {
      _audio?.configureListening(null);
      _host._pushMessage('Could not save the listening statistics setting: $error', level: LogLevel.warning);
      _statsCollectionController.add(_host.statsCollectionEnabled);
      _scheduleStatsRefresh();
    }
  }

  Future<void> resetLocalListeningHistory() =>
      _resetListeningHistory(_host._listeningStats.resetLocalHistory, localOnly: true);

  Future<void> resetListeningStatistics() => _resetListeningHistory(_resetDeviceAndAccountHistory);

  Future<void> resetAccountListeningHistory() async {
    final sync = _listeningSync;

    if (!_host._authState.isAuthorized || sync == null) {
      throw StateError('Connect and sign in to reset account listening statistics.');
    }

    await _resetListeningHistory(sync.resetAccountHistory);
  }

  Future<void> importLocalListeningHistory() async {
    if (_host._disposed || !_host.canImportLocalStats) {
      return;
    }

    await _host._listeningStats.importLocalHistory();
    await _refreshLocalStats();
    await _listeningSync?.sync(immediate: true);
  }

  Future<void> loadStats({int? year, int? month}) async {
    if (_host._disposed) {
      return;
    }

    _stats = StatsResponse(
      year: year ?? _stats?.year ?? DateTime.now().toUtc().year,
      month: month,
      totalMinutes: _stats?.totalMinutes ?? 0,
      totalListeningMs: _stats?.totalListeningMs ?? 0,
      totalPlays: _stats?.totalPlays ?? 0,
      uniqueTracks: _stats?.uniqueTracks ?? 0,
      uniqueArtists: _stats?.uniqueArtists ?? 0,
      otherGenreListeningMs: _stats?.otherGenreListeningMs ?? 0,
      unclassifiedListeningMs: _stats?.unclassifiedListeningMs ?? 0,
      topArtists: _stats?.topArtists ?? [],
      topTracks: _stats?.topTracks ?? [],
      topGenres: _stats?.topGenres ?? [],
    );

    await _refreshLocalStats();
    unawaited(_repairListeningGenreMetadata());
    await _listeningSync?.sync(immediate: true);
    await _refreshLocalStats();
  }

  Future<void> _resetDeviceAndAccountHistory() async {
    final resetServer = _host._authState.isAuthorized;
    final sync = _listeningSync;

    if (sync != null) {
      await sync.resetListeningStatistics(resetServer: resetServer);
    } else {
      if (resetServer) {
        throw StateError('Listening statistics are not ready. Try again.');
      }

      await _host._listeningStats.resetDeviceHistory();
    }
  }

  Future<void> _initializeListeningStats() async {
    void handleHistoryChanged(ListeningStatsSnapshot _) {
      if (_host._disposed) {
        return;
      }

      _host._gaplessCoordinator.listeningChanged();

      _statsCollectionController.add(_host.statsCollectionEnabled);
      _scheduleStatsRefresh();
    }

    _listeningSubscription = _host._listeningStats.changes.listen(handleHistoryChanged);

    try {
      await _host._listeningStats.initialize();

      if (_host._disposed) {
        return;
      }

      final sync = ListeningStatsSync(
        history: _host._listeningStats,
        connection: _host.connection,
        isAuthorized: () => !_host._disposed && _host._authState.isAuthorized,
        onChanged: _scheduleStatsRefresh,
        onIdentity: _saveListeningIdentity,
      );

      sync.start();
      _listeningSync = sync;

      await _refreshLocalStats();
    } catch (error) {
      _host._pushMessage('Listening history storage is unavailable: $error', level: LogLevel.warning);
    }
  }

  Future<void> _saveListeningIdentity(String serverId, String userId) async {
    _statsServerId = serverId;
    _statsUserId = userId;

    final saved = _host._savedCredentials;

    if (saved != null &&
        saved.baseUrl == _host.connection.baseUrl &&
        saved.token == _host.connection.token &&
        (saved.serverId != serverId || saved.userId != userId)) {
      await _host._storeSavedCredentials(
        AuthCredentials(
          baseUrl: saved.baseUrl,
          token: saved.token,
          username: saved.username,
          serverId: serverId,
          userId: userId,
          trust: saved.trust,
        ),
      );
    }

    final track = _host._playbackState.track;

    if (track != null &&
        (_listeningSessionContext?['account_scope'] != _host._listeningStats.accountScope ||
            _listeningSessionContext?['history_generation'] != _host._listeningStats.historyGeneration)) {
      _host._gaplessCoordinator.invalidate();
      _prepareListeningSession(track, newSession: true, updateActive: true);
      _host._gaplessCoordinator.prepare();
    }
  }

  Future<void> _detachListeningAccount({int? expectedSessionRevision}) async {
    _host._gaplessCoordinator.invalidate();
    _statsServerId = _statsUserId = null;
    _listeningSessionContext = null;
    _audio?.configureListening(null, discardPending: false);

    if (_host._listeningStats.storageError == null) {
      try {
        await _host._listeningStats.setAccount();
      } catch (error) {
        _host._pushMessage('Could not switch listening history: $error', level: LogLevel.warning);

        return;
      }
    }

    if (_host._disposed ||
        (expectedSessionRevision != null && _host.connection.sessionRevision != expectedSessionRevision)) {
      return;
    }

    final playback = _host._playbackState;

    if (playback.isLocalPlayback && playback.track != null) {
      _prepareListeningSession(playback.track!, newSession: true, updateActive: true);
      _host._gaplessCoordinator.prepare();
    }

    await _refreshLocalStats();
  }

  void _scheduleStatsRefresh() {
    if (_host._disposed) {
      return;
    }

    _statsRefreshDebounce.schedule(const Duration(milliseconds: 100), () {
      unawaited(_refreshLocalStats());
    });
  }

  Future<void> _refreshLocalStats() async {
    if (_host._disposed || _host._listeningStats.storageError != null) {
      if (!_host._disposed) {
        _statsController.add(_stats);
      }

      return;
    }

    final revision = _statsReads.advance();

    try {
      final result = await _host._listeningStats.stats(year: _stats?.year, month: _stats?.month);

      if (_host._disposed || !_statsReads.isCurrent(revision)) {
        return;
      }

      _stats = result;
      _statsController.add(result);
    } catch (_) {
      if (!_host._disposed) {
        _statsController.add(_stats);
      }
    }
  }

  Future<void> _resetListeningHistory(Future<void> Function() reset, {bool localOnly = false}) async {
    if (_host._disposed || _resettingListeningStats) {
      throw StateError('Listening statistics are unavailable or already resetting.');
    }

    _resettingListeningStats = true;

    final resetActiveSession = !localOnly || _host._listeningStats.accountScope == 'local';

    _suspendedListeningForReset = resetActiveSession;

    if (resetActiveSession) {
      _host._gaplessCoordinator.invalidate();
      _listeningSessionContext = null;
      _audio?.configureListening(null);
    }

    try {
      await reset();
    } finally {
      _resettingListeningStats = false;
      _suspendedListeningForReset = false;

      if (!_host._disposed) {
        final track = _host._playbackState.track;

        if (track != null && (resetActiveSession || (localOnly && _host._listeningStats.accountScope == 'local'))) {
          _prepareListeningSession(track, newSession: true, updateActive: true);
          _host._gaplessCoordinator.prepare();
        }

        await _refreshLocalStats();
      }
    }
  }

  void _recordListeningSegment(Map<String, dynamic> data) {
    if (_listeningClosed || _suspendedListeningForReset || !_host.statsCollectionEnabled) {
      return;
    }

    if (data['collection_revision'] != null &&
        data['collection_revision'] != _host._listeningStats.preferenceRevision) {
      return;
    }

    final scope = data['account_scope']?.toString();
    final generation = (data['history_generation'] as num?)?.toInt();

    try {
      final event = ListeningEvent.fromJson(data);

      unawaited(
        _host._listeningStats.recordSegment(event, scope: scope, generation: generation).catchError((Object error) {
          _host._pushMessage('Listening history could not be saved: $error', level: LogLevel.warning);
        }),
      );
    } catch (error) {
      _host._pushMessage('Listening history could not be recorded: $error', level: LogLevel.warning);
    }
  }

  void _prepareListeningSession(Track track, {bool newSession = false, bool updateActive = false}) {
    if (_suspendedListeningForReset || !_host.statsCollectionEnabled || _host._listeningStats.storageError != null) {
      _audio?.configureListening(null);

      return;
    }

    final previous = _listeningSessionContext;
    final identity = track.serverTrackId ?? track.id;

    if (!newSession &&
        previous?['track_id'] == identity &&
        previous?['account_scope'] == _host._listeningStats.accountScope &&
        previous?['history_generation'] == _host._listeningStats.historyGeneration) {
      _audio?.configureListening(previous, updateActive: updateActive);

      return;
    }

    _listeningSessionContext = _newListeningContext(track);
    _host._pushMessage(
      'Listening genre snapshot: track_id=$identity '
      'artist=${jsonEncode(track.artist)} '
      'track_tags=${jsonEncode(track.genres)} '
      'listening_genres=${jsonEncode(_listeningSessionContext?['genres'])}',
      level: LogLevel.debug,
    );
    _audio?.configureListening(_listeningSessionContext, updateActive: updateActive);
  }

  /// Builds a fresh occurrence context without touching the active recorder.
  Map<String, dynamic>? _newListeningContext(Track track) {
    if (_suspendedListeningForReset || !_host.statsCollectionEnabled || _host._listeningStats.storageError != null) {
      return null;
    }
    final now = _host._playbackClock().toUtc().millisecondsSinceEpoch;
    final canUseServerMetadata = track.serverBaseUrl == null || track.serverBaseUrl == _host.connection.baseUrl;
    final template = ListeningEvent.fromTrack(
      track: track,
      sessionId: newListeningId(),
      deviceId: _host._listeningStats.deviceId,
      sessionStartedAtMs: now,
      startedAtMs: now,
      endedAtMs: now,
      listenedMs: 0,
      cachedAlbums: canUseServerMetadata ? _host._albums : const [],
      cachedArtists: canUseServerMetadata ? _host._artists : const [],
    );

    return {
      ...template.toJson(),
      'account_scope': _host._listeningStats.accountScope,
      'history_generation': _host._listeningStats.historyGeneration,
      'collection_revision': _host._listeningStats.preferenceRevision,
    };
  }

  Future<void> _repairListeningGenreMetadata() {
    final running = _statsGenreRepair;
    if (running != null) {
      return running;
    }

    void reportRepairFailure(Object error) {
      if (!_host._disposed) {
        _host._pushMessage('Listening genre metadata could not be refreshed: $error', level: LogLevel.debug);
      }
    }

    final work = _resolveListeningGenreMetadata().catchError(reportRepairFailure);

    _statsGenreRepair = work;

    void clearCompletedRepair() {
      if (identical(_statsGenreRepair, work)) {
        _statsGenreRepair = null;
      }
    }

    return work.whenComplete(clearCompletedRepair);
  }

  Future<void> _resolveListeningGenreMetadata() async {
    if (_host._disposed || _host._listeningStats.storageError != null) {
      return;
    }

    final scope = _host._listeningStats.accountScope;
    final generation = _host._listeningStats.historyGeneration;
    final revision = _host.connection.sessionRevision;
    final server = _host.connection.baseUrl;

    bool current() =>
        !_host._disposed &&
        scope == _host._listeningStats.accountScope &&
        generation == _host._listeningStats.historyGeneration &&
        revision == _host.connection.sessionRevision;

    final key = (scope: scope, generation: generation, revision: revision);

    if (_statsGenreRepairCursorKey != key) {
      _statsGenreRepairCursorKey = key;
      _statsGenreRepairAfterTrackId = null;
    }

    var candidates = await _host._listeningStats.genreMetadataCandidateEvents(
      afterTrackId: _statsGenreRepairAfterTrackId,
    );

    if (current() && candidates.isEmpty && _statsGenreRepairAfterTrackId != null) {
      _statsGenreRepairAfterTrackId = null;
      candidates = await _host._listeningStats.genreMetadataCandidateEvents();
    }

    if (!current() || candidates.isEmpty) {
      return;
    }

    final cached = <String, Track>{};

    for (final track in [
      if (scope != 'local') ...[..._host._tracks, ..._host._playlistTracks, ..._host._liked, ..._host._playQueue],
      ..._host.offlineLibrarySnapshot.tracks,
    ]) {
      // In-memory catalog tracks without an origin can survive a connection
      // switch. Only downloads with a known matching origin are authoritative.
      if (scope != 'local' && track.serverBaseUrl != server) {
        continue;
      }

      cached[track.serverTrackId ?? track.id] = track;
    }

    final albums = <String, Future<Album>>{};

    Future<Album> album(String id) => albums.putIfAbsent(id, () => _host.connection.fetchAlbumById(id));

    List<String> genres(Track track, {Album? release}) {
      final useCatalog = scope != 'local' && (track.serverBaseUrl == null || track.serverBaseUrl == server);

      return ListeningEvent.fromTrack(
        track: track,
        sessionId: '',
        deviceId: '',
        sessionStartedAtMs: 0,
        startedAtMs: 0,
        endedAtMs: 0,
        listenedMs: 0,
        eventId: '',
        cachedAlbums: [if (release != null) release, if (useCatalog) ..._host._albums],
        cachedArtists: useCatalog ? _host._artists : const [],
      ).genres;
    }

    Future<MapEntry<String, List<String>>?> resolve(ListeningEvent saved) async {
      if (!current()) {
        return null;
      }

      final known = cached[saved.trackId];

      if (known != null && (known.listeningGenres.isNotEmpty || known.offlineAlbum?.genres.isNotEmpty == true)) {
        return MapEntry(saved.trackId, genres(known));
      }

      if (scope == 'local' || !_host._authState.isAuthorized) {
        return null;
      }

      try {
        final track = await _host.connection.fetchTrackById(saved.trackId);

        if (!current()) {
          return null;
        }

        Album? release;

        if (track.listeningGenres.isEmpty && track.albumId?.isNotEmpty == true) {
          try {
            release = await album(track.albumId!);
          } on ApiException catch (albumError) {
            if (albumError.statusCode != 404) {
              rethrow;
            }
          }
        }

        return MapEntry(saved.trackId, genres(track, release: release));
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }

        if (saved.albumId.isEmpty || !current()) {
          return null;
        }

        // A removed recording can still have its identified release in the
        // catalog. Never match unrelated releases or artists by display name.
        try {
          final release = await album(saved.albumId);

          if (release.id == saved.albumId && release.genres.isNotEmpty) {
            return MapEntry(saved.trackId, release.genres);
          }
        } on ApiException catch (albumError) {
          if (albumError.statusCode != 404) {
            rethrow;
          }
        }

        return null;
      }
    }

    // A screen refresh repairs at most 50 historical tracks. Existing maps
    // persist. The cursor advances past missing recordings and wraps so that
    // temporary failures can be retried without starving later recordings.
    final metadata = <String, List<String>>{};
    var failed = 0;
    Object? lastError;

    Future<MapEntry<String, List<String>>?> resolveSafely(ListeningEvent saved) async {
      try {
        return await resolve(saved);
      } catch (error) {
        failed++;
        lastError = error;

        return null;
      }
    }

    try {
      for (var offset = 0; offset < candidates.length && current(); offset += 4) {
        final batch = candidates.skip(offset).take(4);
        final results = await Future.wait(batch.map(resolveSafely));

        if (!current()) {
          return;
        }

        for (final entry in results) {
          if (entry != null) {
            metadata[entry.key] = entry.value;
          }
        }
      }

      if (current()) {
        _statsGenreRepairAfterTrackId = candidates.last.trackId;

        if (failed > 0) {
          _host._pushMessage('Genre metadata refresh skipped $failed recordings: $lastError', level: LogLevel.debug);
        }
      }
    } finally {
      if (current() && metadata.isNotEmpty) {
        await _host._listeningStats.updateGenreMetadata(metadata, scope: scope, generation: generation);
      }
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _ListeningStatsFacade {
  _ListeningStatsCoordinator get _statsCoordinator;

  AudioEngine? get _audio => _statsCoordinator._audio;

  set _audio(AudioEngine? value) => _statsCoordinator._audio = value;

  ListeningStatsSync? get _listeningSync => _statsCoordinator._listeningSync;

  StreamSubscription<ListeningStatsSnapshot>? get _listeningSubscription => _statsCoordinator._listeningSubscription;

  DebouncedAction get _statsRefreshDebounce => _statsCoordinator._statsRefreshDebounce;

  StreamController<bool> get _statsCollectionController => _statsCoordinator._statsCollectionController;

  set _listeningSessionContext(Map<String, dynamic>? value) => _statsCoordinator._listeningSessionContext = value;

  set _listeningClosed(bool value) => _statsCoordinator._listeningClosed = value;

  String? get _statsServerId => _statsCoordinator._statsServerId;

  set _statsServerId(String? value) => _statsCoordinator._statsServerId = value;

  String? get _statsUserId => _statsCoordinator._statsUserId;

  set _statsUserId(String? value) => _statsCoordinator._statsUserId = value;

  Stream<bool> get statsCollectionEnabledStream => _statsCoordinator.statsCollectionEnabledStream;

  bool get statsSyncing => _statsCoordinator.statsSyncing;

  String? get statsSyncMessage => _statsCoordinator.statsSyncMessage;

  bool get statsServerCollectionEnabled => _statsCoordinator.statsServerCollectionEnabled;

  bool get canImportLocalStats => _statsCoordinator.canImportLocalStats;

  StreamController<StatsResponse?> get _statsController => _statsCoordinator._statsController;

  set _stats(StatsResponse? value) => _statsCoordinator._stats = value;

  Stream<StatsResponse?> get statsStream => _statsCoordinator.statsStream;

  StatsResponse? get stats => _statsCoordinator.stats;

  Future<void> setStatsCollectionEnabled(bool value) => _statsCoordinator.setStatsCollectionEnabled(value);

  Future<void> resetLocalListeningHistory() => _statsCoordinator.resetLocalListeningHistory();

  Future<void> resetListeningStatistics() => _statsCoordinator.resetListeningStatistics();

  Future<void> resetAccountListeningHistory() => _statsCoordinator.resetAccountListeningHistory();

  Future<void> importLocalListeningHistory() => _statsCoordinator.importLocalListeningHistory();

  Future<void> loadStats({int? year, int? month}) => _statsCoordinator.loadStats(year: year, month: month);

  Future<void> _initializeListeningStats() => _statsCoordinator._initializeListeningStats();

  Future<void> _detachListeningAccount({int? expectedSessionRevision}) =>
      _statsCoordinator._detachListeningAccount(expectedSessionRevision: expectedSessionRevision);

  Future<void> _refreshLocalStats() => _statsCoordinator._refreshLocalStats();

  void _recordListeningSegment(Map<String, dynamic> data) => _statsCoordinator._recordListeningSegment(data);

  void _prepareListeningSession(Track track, {bool newSession = false, bool updateActive = false}) =>
      _statsCoordinator._prepareListeningSession(track, newSession: newSession, updateActive: updateActive);
}
