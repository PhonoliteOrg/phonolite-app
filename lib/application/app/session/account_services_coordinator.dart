part of '../app_controller.dart';

/// Assembles account domains around the shared snapshot reconciliation owner.
class _AccountServicesCoordinator {
  final AppController _host;
  final _requests = RequestGeneration();
  final _presets = StreamController<List<ShufflePreset>>.broadcast();
  final _accountStates = StreamController<AccountState?>.broadcast();
  final _trackReportRetry = DebouncedAction();
  final Map<int, int> _pendingPresetWrites = {};
  late final RevisionSnapshotSync<AccountState, AccountRevisions> _sync = RevisionSnapshotSync(
    openStream: _openEvents,
    fetchSnapshot: _host.connection.fetchAccountState,
    applySnapshot: _applyState,
    isSessionCurrent: _isCurrent,
    onDiagnostic: AppLogger.debug,
    onUnauthorized: _requireSignIn,
    onUnsupported: _disableEvents,
    revisionOf: (state) => state.revisions,
    merge: (first, second) => first.merge(second),
    isAhead: (first, second) => first.isAheadOf(second),
    isRollback: (first, second) => first.isBehind(second),
    refreshUnchangedEvents: true,
  );
  ServerCapabilities? _capabilities;
  AccountState? _state;
  String? _accountIdentity;
  AccountRevisions? _applied;
  List<ShufflePreset> _items = const [];
  int? _session;
  int _presetMutation = 0;
  int _eventEpoch = 0;
  Timer? _uploadTimer;
  bool _eventsEnabled = false;
  int? _seedSession;
  String _playbackSession = '';
  int _trackSequence = 0;
  int _selection = 0;
  int? _reportedSelection;

  _AccountServicesCoordinator(this._host);

  List<ShufflePreset> get presets => List.unmodifiable(_items);

  Stream<List<ShufflePreset>> get changes => _presets.stream;

  AccountState? get state => _state;

  Stream<AccountState?> get accountChanges => _accountStates.stream;

  bool get presetsAvailable =>
      _session == _host.connection.sessionRevision &&
      _accountIdentity != null &&
      (_capabilities?.shufflePresets ?? false);

  bool get sessionsAvailable =>
      _session == _host.connection.sessionRevision && (_capabilities?.sessionManagement ?? false);

  void start(ServerCapabilities capabilities) {
    final session = _host.connection.sessionRevision;

    if (_host._disposed || !_host._authState.isAuthorized || _session == session) {
      return;
    }

    if (_session != null) {
      unawaited(stop());
    }

    _requests.advance();
    _session = session;
    _capabilities = capabilities;
    _host._authController.add(_host._authState);
    _playbackSession = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _trackSequence = 0;
    _reportedSelection = null;
    _trackReportRetry.cancel();
    _eventsEnabled = capabilities.accountEventsV2;
    _host._resumeCoordinator.start(capabilities);

    if (_eventsEnabled) {
      _sync.start(baseUrl: _host.connection.baseUrl, token: _host.connection.token!);
      _uploadTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_host._authState.isAuthorized && _host._playbackState.isPlaying && _host.statsCollectionEnabled) {
          unawaited(_host._listeningSync?.sync() ?? Future<void>.value());
        }
      });
    }

    if (capabilities.lastTrack && !capabilities.playbackResume && _seedSession != session) {
      _seedSession = session;
      unawaited(_initializeStartingTrack());
    }
  }

  Future<void> stop() {
    _host._resumeCoordinator.detachAccount();
    _requests.advance();
    _session = null;
    _capabilities = null;
    _host._preferencesCoordinator._setShuffleAccount(null);
    _eventsEnabled = false;
    _applied = null;
    _state = null;
    _accountIdentity = null;
    _accountStates.add(null);
    _items = const [];
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _reportedSelection = null;
    _trackReportRetry.cancel();
    _presets.add(const []);

    return _sync.stop();
  }

  Future<void> close() async {
    await stop();
    await _presets.close();
    await _accountStates.close();
  }

  void refresh() {
    if (_eventsEnabled) {
      _sync.refresh();
    }
  }

  Future<void> loadPresets() async {
    if (!presetsAvailable) {
      return;
    }

    final session = _host.connection.sessionRevision;
    final mutation = _presetMutation;
    final snapshot = await _host.connection.fetchShufflePresets();

    if (_host._sessionCoordinator._isServerSessionCurrent(session) &&
        mutation == _presetMutation &&
        (_pendingPresetWrites[session] ?? 0) == 0) {
      _items = snapshot.items;
      _presets.add(presets);
    }
  }

  Future<void> savePreset({
    String? id,
    required String name,
    required List<String> artistIds,
    required List<String> genres,
    int? expectedRevision,
  }) async {
    if (!presetsAvailable) {
      throw StateError('Connect to a server supporting saved shuffles.');
    }

    final session = _host.connection.sessionRevision;
    final mutation = ++_presetMutation;
    _pendingPresetWrites[session] = (_pendingPresetWrites[session] ?? 0) + 1;

    try {
      final saved = id == null
          ? await _host.connection.createShufflePreset(name: name, artistIds: artistIds, genres: genres)
          : await _host.connection.updateShufflePreset(
              id,
              name: name,
              artistIds: artistIds,
              genres: genres,
              expectedRevision: expectedRevision ?? -1,
            );

      if (_host._sessionCoordinator._isServerSessionCurrent(session) &&
          mutation == _presetMutation &&
          !_items.any((item) => item.id == saved.id && item.revision > saved.revision)) {
        _items = [
          for (final item in _items)
            if (item.id != saved.id) item,
          saved,
        ];
        _presets.add(presets);
      }
    } finally {
      _finishPresetWrite(session);
      _presetMutation++;
      refresh();
    }
  }

  Future<void> deletePreset(ShufflePreset preset) async {
    if (!presetsAvailable) {
      throw StateError('Connect to a server supporting saved shuffles.');
    }

    final session = _host.connection.sessionRevision;
    final mutation = ++_presetMutation;
    _pendingPresetWrites[session] = (_pendingPresetWrites[session] ?? 0) + 1;

    try {
      await _host.connection.deleteShufflePreset(preset.id, expectedRevision: preset.revision);

      if (_host._sessionCoordinator._isServerSessionCurrent(session) && mutation == _presetMutation) {
        _items = _items.where((item) => item.id != preset.id).toList();
        _presets.add(presets);
      }
    } finally {
      _finishPresetWrite(session);
      _presetMutation++;
      refresh();
    }
  }

  Future<void> applyPreset(ShufflePreset preset) async {
    final current = _items.where((item) => item.id == preset.id).firstOrNull;

    if (!presetsAvailable || current == null) {
      throw StateError('This saved shuffle is no longer available.');
    }

    final session = _host.connection.sessionRevision;
    await _host.updateCustomShuffleSettings(artistIds: current.artistIds, genres: current.genres);

    if (!_host._sessionCoordinator._isServerSessionCurrent(session)) {
      return;
    }

    _host.updateShuffleMode(ShuffleMode.custom, scope: ActionScope.server);
  }

  Future<void> importPreset() async {
    final session = _host.connection.sessionRevision;
    final legacy = await _host._customShuffleStorage.read();

    if (!_host._sessionCoordinator._isServerSessionCurrent(session)) {
      return;
    }

    await savePreset(name: 'Imported custom shuffle', artistIds: legacy.artistIds, genres: legacy.genres);
  }

  Future<int> revokeOthers() async {
    if (!sessionsAvailable) {
      throw StateError('Session management is unavailable.');
    }

    final session = _host.connection.sessionRevision;
    final count = await _host.connection.revokeOtherSessions();

    if (!_host._sessionCoordinator._isServerSessionCurrent(session)) {
      throw StateError('The signed-in account changed.');
    }

    return count;
  }

  Future<void> revokeAll() async {
    if (!sessionsAvailable) {
      throw StateError('Session management is unavailable.');
    }

    final session = _host.connection.sessionRevision;
    try {
      await _host.connection.revokeAllSessions();
    } catch (_) {
      // The revocation stream can sign this session out before its HTTP reply.
      if (_host.connection.sessionRevision != session && !_host._authState.isAuthorized) {
        return;
      }

      rethrow;
    }

    if (_host._sessionCoordinator._isServerSessionCurrent(session)) {
      await _host._sessionCoordinator.requireSignIn(reason: 'All devices were signed out. Sign in again.');
    }
  }

  /// Marks a deliberate track selection, before the audio engine starts it.
  void prepareTrackStart() => retireTrackStart();

  void retireTrackStart() {
    _host._resumeCoordinator.retireSelection();
    _selection++;
    _trackReportRetry.cancel();
  }

  void reportStartedTrack() {
    _host._resumeCoordinator.started();
    if (_capabilities?.playbackResume ?? false) return;

    final track = _host._playbackState.track;

    if (_host._disposed ||
        !(_capabilities?.lastTrack ?? false) ||
        !_host._authState.isAuthorized ||
        track == null ||
        _host._playbackState.isLocalPlayback ||
        _reportedSelection == _selection) {
      return;
    }

    _reportedSelection = _selection;
    final sequence = ++_trackSequence;
    final session = _host.connection.sessionRevision;
    final selection = _selection;
    final playbackSession = _playbackSession;
    final request = _requests.current;

    bool isCurrent() =>
        !_host._disposed &&
        _requests.isCurrent(request) &&
        _host._sessionCoordinator._isServerSessionCurrent(session) &&
        _selection == selection &&
        _host._playbackState.track?.id == track.id &&
        !_host._playbackState.isLocalPlayback;

    Future<void> send({bool retry = false}) async {
      if (!isCurrent()) {
        return;
      }

      try {
        await _host.connection.reportAccountTrackStart(
          trackId: track.serverTrackId ?? track.id,
          sessionId: playbackSession,
          sequence: sequence,
          requestId: '$playbackSession-$sequence',
        );
      } catch (error) {
        AppLogger.debug('Could not remember the started track: $error');
        final transient =
            error is! ApiException || error.statusCode == 408 || error.statusCode == 429 || error.statusCode >= 500;

        if (!retry && transient && isCurrent()) {
          // One idempotent retry while this exact session/selection remains active.
          // Stops and later selections retire it; no offline reports are queued.
          _trackReportRetry.schedule(const Duration(seconds: 1), () => unawaited(send(retry: true)));
        }
      }
    }

    unawaited(send());
  }

  bool _isCurrent(String baseUrl, String token) =>
      !_host._disposed &&
      _eventsEnabled &&
      _host._authState.isAuthorized &&
      _session == _host.connection.sessionRevision &&
      _host.connection.baseUrl == baseUrl &&
      _host.connection.token == token;

  void _requireSignIn() =>
      unawaited(_host._sessionCoordinator.requireSignIn(reason: 'Your server session ended. Sign in again.'));

  void _disableEvents() => _eventsEnabled = false;

  Stream<RevisionEvent<AccountRevisions>> _openEvents() => _host.connection.streamAccountEvents().map((event) {
    if (event.kind == RevisionEventKind.ready) {
      _eventEpoch++;
      _applied = null;
    }

    return event;
  });

  void _finishPresetWrite(int session) {
    final remaining = (_pendingPresetWrites[session] ?? 1) - 1;

    if (remaining == 0) {
      _pendingPresetWrites.remove(session);
    } else {
      _pendingPresetWrites[session] = remaining;
    }
  }

  Future<void> _applyState(AccountState state) async {
    final session = _host.connection.sessionRevision;
    final mutation = _presetMutation;
    final previous = _applied;
    final epoch = _eventEpoch;

    if (!_host._sessionCoordinator._isServerSessionCurrent(session) || _session != session || !_eventsEnabled) {
      throw StateError('Account session changed.');
    }

    final origin = ServerTrust.origin(Uri.parse(_host.connection.baseUrl));
    final trust = _host.connection.trust;
    final identity = trust == null ? origin : '${trust.spki}/${trust.opaqueKey}';
    _host._preferencesCoordinator._setShuffleAccount('$origin/$identity/${state.userId}');

    if (_accountIdentity != state.userId) {
      _accountIdentity = state.userId;
      _host._authController.add(_host._authState);
    }

    if ((_pendingPresetWrites[session] ?? 0) != 0) {
      throw StateError('Saved shuffles are being edited.');
    }

    final snapshot =
        (_capabilities?.shufflePresets ?? false) && (previous == null || previous.presets != state.revisions.presets)
        ? await _host.connection.fetchShufflePresets()
        : null;

    if (previous == null || previous.statistics != state.revisions.statistics) {
      await _host._listeningSync?.refreshFromServer();
    }

    if (previous == null || previous.playback != state.revisions.playback) {
      unawaited(_host._resumeCoordinator.refreshAccount());
    }

    if (_host._disposed ||
        !_host._sessionCoordinator._isServerSessionCurrent(session) ||
        _session != session ||
        !_eventsEnabled ||
        mutation != _presetMutation ||
        epoch != _eventEpoch ||
        (_pendingPresetWrites[session] ?? 0) != 0) {
      throw StateError('Account snapshot superseded.');
    }

    if (snapshot != null) {
      _items = snapshot.items;
      _presets.add(presets);
    }

    _state = state;
    _accountStates.add(state);
    _host._sessionCoordinator._updateAccountUsername(state.username);
    _applied = state.revisions;
  }

  Future<void> _initializeStartingTrack() async {
    final session = _host.connection.sessionRevision;
    final request = _requests.current;
    final playback = _host._playbackStarts.current;

    bool isCurrent() =>
        !_host._disposed &&
        _requests.isCurrent(request) &&
        _host._sessionCoordinator._isServerSessionCurrent(session) &&
        playback == _host._playbackStarts.current &&
        _host._playbackState.track == null &&
        _host._playQueue.isEmpty;

    if (!isCurrent()) {
      return;
    }

    try {
      final reference = await _host.connection.fetchAccountLastTrack();

      if (!isCurrent() || reference.trackId == null) {
        return;
      }

      final track = await _host.connection.fetchTrackById(reference.trackId!);

      if (!isCurrent()) {
        return;
      }

      _host._playQueue = [track];
      _host._playIndex = 0;
      prepareTrackStart();
      _host._updatePlayback(
        track: track,
        isPlaying: false,
        isLoading: false,
        position: Duration.zero,
        duration: Duration(milliseconds: track.durationMs),
        bufferRatio: 0,
        queueSource: PlaybackQueueSource.none,
        localPlaybackSource: LocalPlaybackSource.none,
        isLocalPlayback: false,
      );
    } catch (error) {
      AppLogger.debug('Remembered starting track is unavailable: $error');
    }
  }
}
