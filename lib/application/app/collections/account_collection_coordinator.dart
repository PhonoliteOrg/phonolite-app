part of '../app_controller.dart';

/// Connects account reconciliation to the app's existing state owners.
class _AccountCollectionCoordinator {
  final AppController _host;
  final _starts = RequestGeneration();
  final Map<int, int> _activeMutations = {};
  late final AccountCollectionSync _sync = AccountCollectionSync(
    openStream: _host.connection.streamCollectionEvents,
    fetchSnapshot: _host.connection.fetchCollectionSnapshot,
    applySnapshot: _applySnapshot,
    isSessionCurrent: _isSessionCurrent,
    onDiagnostic: AppLogger.debug,
    onUnauthorized: _requireSignIn,
    onUnsupported: _disable,
  );
  int? _sessionRevision;
  int _mutationRevision = 0;
  int _negotiationAttempts = 0;
  Timer? _negotiationRetryTimer;
  bool _enabled = false;
  bool _hasSnapshot = false;

  _AccountCollectionCoordinator(this._host);

  bool get hasSnapshot => _enabled && _hasSnapshot && _sessionRevision == _host.connection.sessionRevision;

  Future<void> start() async {
    final revision = _host.connection.sessionRevision;

    if (_host._disposed || !_host._authState.isAuthorized || _sessionRevision == revision) {
      return;
    }

    final request = _starts.advance();
    _negotiationRetryTimer?.cancel();
    _negotiationRetryTimer = null;
    _sessionRevision = revision;
    _enabled = false;
    _hasSnapshot = false;
    _host.connection.clearCollectionSnapshot();
    await _sync.stop();

    if (!_canStart(request, revision)) {
      return;
    }

    try {
      final capabilities = await _host.connection.fetchCapabilities();

      if (!_canStart(request, revision)) {
        return;
      }

      _host._accountServices.start(capabilities);

      if (!capabilities.accountCollectionsSync) {
        return;
      }

      final token = _host.connection.token;

      if (token == null || token.isEmpty) {
        return;
      }

      _enabled = true;
      _negotiationAttempts = 0;
      _sync.start(baseUrl: _host.connection.baseUrl, token: token);
    } catch (error) {
      if (_canStart(request, revision)) {
        _sessionRevision = null;
        AppLogger.debug('Could not negotiate account collection sync: $error');
        final delay = Duration(seconds: min(30, 1 << min(_negotiationAttempts++, 5)));
        _negotiationRetryTimer = Timer(delay, () {
          _negotiationRetryTimer = null;

          if (_canStart(request, revision)) {
            unawaited(start());
          }
        });
      }
    }
  }

  Future<void> stop() {
    _starts.advance();
    _negotiationRetryTimer?.cancel();
    _negotiationRetryTimer = null;
    _negotiationAttempts = 0;
    _sessionRevision = null;
    _enabled = false;
    _hasSnapshot = false;
    _host.connection.clearCollectionSnapshot();

    return _sync.stop();
  }

  void refresh() {
    if (_host._disposed || !_host._authState.isAuthorized) {
      return;
    }

    if (_enabled) {
      _sync.refresh();
    } else {
      unawaited(start());
    }
  }

  /// The returned release must run in finally, after publishing the write result.
  void Function() beginMutation() {
    final session = _host.connection.sessionRevision;
    var released = false;
    _activeMutations[session] = (_activeMutations[session] ?? 0) + 1;
    _mutationRevision++;

    void finishMutation() {
      if (released) {
        return;
      }

      released = true;
      final remaining = (_activeMutations[session] ?? 1) - 1;

      if (remaining == 0) {
        _activeMutations.remove(session);
      } else {
        _activeMutations[session] = remaining;
      }

      if (_host.connection.sessionRevision == session) {
        _mutationRevision++;
        refresh();
      }
    }

    return finishMutation;
  }

  void publishMembership() {
    _host._libraryCoordinator._updateLoadedTrackMetadata(_host.connection.projectServerTrack);
  }

  bool _canStart(int request, int revision) =>
      _starts.isCurrent(request) && _host._sessionCoordinator._isServerSessionCurrent(revision);

  bool _isSessionCurrent(String baseUrl, String token) =>
      !_host._disposed &&
      _enabled &&
      _host._authState.isAuthorized &&
      _host.connection.sessionRevision == _sessionRevision &&
      _host.connection.baseUrl == baseUrl &&
      _host.connection.token == token;

  void _requireSignIn() {
    if (!_host._disposed && _host._authState.isAuthorized) {
      unawaited(_host._sessionCoordinator.requireSignIn(reason: 'Your server session ended. Sign in again.'));
    }
  }

  void _disable() {
    _enabled = false;
    _hasSnapshot = false;
    _host.connection.clearCollectionSnapshot();
  }

  Future<void> _applySnapshot(AccountCollectionSnapshot snapshot) async {
    final session = _host.connection.sessionRevision;
    final mutation = _mutationRevision;

    bool isCurrent() =>
        _enabled &&
        _host._sessionCoordinator._isServerSessionCurrent(session) &&
        _sessionRevision == session &&
        mutation == _mutationRevision &&
        (_activeMutations[session] ?? 0) == 0;

    if (!isCurrent()) {
      throw StateError('Collection snapshot superseded by a local write');
    }

    final likes = snapshot.likes.where((like) => like.liked).toList();
    likes.sort((first, second) => second.updatedAt.compareTo(first.updatedAt));
    final likedIds = likes.map((like) => like.trackId).toSet();
    final likedTracks = likedIds.isEmpty ? const <Track>[] : await _host.connection.fetchLikedTracks();
    final openPlaylistId = _host._currentPlaylistId;
    final openPlaylistExists = snapshot.playlists.any((playlist) => playlist.id == openPlaylistId);
    var openTracks = const <Track>[];

    if (openPlaylistId != null && openPlaylistExists) {
      try {
        openTracks = await _host.connection.fetchPlaylistTracks(openPlaylistId);
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }

        throw StateError('Playlist changed while resolving its collection snapshot');
      }
    }

    if (!isCurrent()) {
      throw StateError('Collection snapshot superseded while loading track metadata');
    }

    final knownTracks = <String, Track>{
      for (final track in [
        ..._host._tracks,
        ..._host._playlistTracks,
        ..._host._liked,
        ..._host._playQueue,
        if (_host._playbackState.track != null) _host._playbackState.track!,
        ...likedTracks,
      ])
        if (track.localId == null) track.id: track,
    };

    // A track may leave the server's liked list between the state snapshot and
    // metadata read. Fetch its metadata directly rather than losing the row.
    for (final id in likedIds.difference(knownTracks.keys.toSet())) {
      try {
        knownTracks[id] = await _host.connection.fetchTrackById(id);
      } on ApiException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }
      }
    }

    if (!isCurrent()) {
      throw StateError('Collection snapshot superseded while resolving liked tracks');
    }

    _host.connection.applyCollectionSnapshot(snapshot);
    _hasSnapshot = true;
    _host._favoritesCoordinator._applyCollectionSnapshot([
      for (final id in likedIds)
        if (knownTracks[id] case final track?) _host.connection.projectServerTrack(track),
    ]);
    _host._playlistsCoordinator._applyCollectionSnapshot(snapshot.playlists, openPlaylistId, openTracks);
    publishMembership();
    await _host._pushNowPlayingUpdate(force: true);
  }
}
