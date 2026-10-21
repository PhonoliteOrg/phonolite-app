part of 'package:phonolite_app/application/app/app_controller.dart';

class _SessionCoordinator {
  final AppController _host;
  AuthCredentials? _savedCredentials;
  Future<void> _savedCredentialsWriteChain = Future<void>.value();
  bool _resettingUserPassword = false;
  bool _restoringSession = false;
  bool _savedCredentialsInvalidated = false;
  final _sessionRestores = RequestGeneration();
  final _authController = StreamController<AuthState>.broadcast();
  late AuthState _authState;
  int _artistListSessionRevision = -1;

  _SessionCoordinator(this._host);

  Stream<AuthState> get authStream => _authController.stream;

  AuthState get authState => _authState;

  bool get hasSavedCredentials => _savedCredentials != null;

  String? get savedUsername => _savedCredentials?.username;

  String? get savedBaseUrl => _savedCredentials?.baseUrl;

  bool get canUseServer => _authState.isAuthorized;

  bool get canResetUserPassword =>
      !_host._disposed &&
      !_resettingUserPassword &&
      _authState.isAuthorized &&
      _authState.baseUrl == _host.connection.baseUrl &&
      _host.connection.canChangeOwnPassword;

  bool get _canAttemptRemotePlayback {
    final token = _host.connection.token;

    return token != null && token.isNotEmpty && _authState.hasSession;
  }

  bool get _shouldAutoReconnectServer {
    final token = _host.connection.token;

    return _authState.status == SessionStatus.serverUnavailable && token != null && token.isNotEmpty;
  }

  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    _host._statsServerId = _host._statsUserId = null;

    if (_host._listeningStats.storageError == null) {
      await _host._listeningStats.setAccount();
    }

    _host._listeningSessionContext = null;

    final playingTrack = _host._playbackState.track;

    if (playingTrack != null) {
      _host._prepareListeningSession(playingTrack, newSession: true, updateActive: true);
    }

    _setSessionStatus(SessionStatus.checking, error: null);

    try {
      _host.connection.setBaseUrl(baseUrl);

      final token = await _host.connection.login(username: username, password: password);

      await _host._refreshServerPorts();
      _host._serverHealthFailureCount = 0;
      _setAuthorized(true, error: null);

      await _host._loadPlaybackSettings();
      unawaited(_host._offlineDownloadManager.resumePausedForCurrentServer());
      unawaited(_host._offlineDownloadManager.repairOfflineMetadataFragments());

      if (rememberMe) {
        final credentials = AuthCredentials(
          baseUrl: _host.connection.baseUrl,
          token: token,
          username: username,
          serverId: _host._statsServerId,
          userId: _host._statsUserId,
          trust: _host.connection.trust!,
        );

        await _storeSavedCredentials(credentials);
      } else {
        await _clearSavedCredentials();
      }
    } on ApiException catch (err) {
      final message = '${_host._formatApiError(err)} (OPAQUE sign-in)';

      _setSessionStatus(SessionStatus.serverReachable, error: message);
      _host._pushMessage('Login failed: $message', level: LogLevel.error);
    } catch (err) {
      _setSessionStatus(SessionStatus.offline, error: serverFailureMessage(err));
      _host._pushMessage('Login failed: $err', level: LogLevel.error);
    }
  }

  void loginWithToken({required String baseUrl, required String token}) {
    _host._statsServerId = _host._statsUserId = null;
    _host._listeningSessionContext = null;
    _host._audio?.configureListening(null, discardPending: false);

    final resetStatsAccount = _host._listeningStats.storageError == null
        ? _host._listeningStats.setAccount()
        : Future<void>.value();

    _host.connection.setBaseUrl(baseUrl);
    _host.connection.setToken(token);
    _host._serverHealthFailureCount = 0;
    _setAuthorized(true, error: null);

    Future<void> initializeTokenSession() async {
      await resetStatsAccount;

      final playingTrack = _host._playbackState.track;

      if (!_host._disposed && playingTrack != null) {
        _host._prepareListeningSession(playingTrack, newSession: true, updateActive: true);
      }

      await _host._refreshLocalStats();
      await _host._refreshServerPorts();
      await _host._loadPlaybackSettings();
      await _host._offlineDownloadManager.resumePausedForCurrentServer();
      unawaited(_host._offlineDownloadManager.repairOfflineMetadataFragments());
    }

    initializeTokenSession();
  }

  Future<bool> probeServer(String input) async {
    _setSessionStatus(SessionStatus.checking, error: null);

    try {
      final resolved = await _host.connection.resolveBaseUrl(input);

      var identityChanged = false;
      try {
        await _host.connection.verifyServerConnection(resolved);
      } on ServerConnectionCheckException catch (error) {
        if (error.reason != ServerConnectionFailure.identityChanged) rethrow;
        // Reachability cannot trust this key. Only password sign-in can verify
        // it against the saved OPAQUE identity and commit a replacement pin.
        identityChanged = true;
      }

      if (_host._disposed) {
        return false;
      }

      _host.connection.setBaseUrl(resolved);
      _host._serverHealthFailureCount = 0;
      // Reachability is confirmed; OPAQUE sign-in authenticates the account and
      // establishes server trust before any credentials or tokens can be used.
      _setSessionStatus(
        SessionStatus.serverReachable,
        error: identityChanged ? 'Server keys changed. Sign in again to verify the new server key.' : null,
      );

      return true;
    } catch (err) {
      final message = serverFailureMessage(err);

      _setSessionStatus(SessionStatus.offline, error: message);
      _host._pushMessage('Server connection failed: $message', level: LogLevel.warning);

      return false;
    }
  }

  Future<void> logout({bool clearSaved = true}) async {
    final serverBaseUrl = _host.connection.baseUrl;
    final preserveLocalPlayback = _host._playbackState.isLocalPlayback && _host._playbackState.track != null;

    _host._stopMetadataEventListener();
    _beginBestEffortServerLogout();
    _pauseDownloadsForDisconnectedServer(serverBaseUrl);

    _host.connection.setToken(null);
    _host._serverHealthFailureCount = 0;
    _host._serverReconnectAttempt = 0;
    _setSessionStatus(SessionStatus.offline, error: null);

    await _host._detachListeningAccount();

    _host._quicPort = null;

    if (preserveLocalPlayback) {
      _host._closeStreamControl();
    } else {
      _clearPlaybackForServerDisconnect();
    }

    if (clearSaved) {
      await _clearSavedCredentials();
    }
  }

  Future<void> resetUserPassword({required String currentPassword, required String newPassword}) async {
    if (!_host.canResetUserPassword) {
      throw PasswordChangeException('Connect to your authenticated server before resetting your password.');
    }

    final baseUrl = _host.connection.baseUrl;
    final token = _host.connection.token;
    final revision = _host.connection.sessionRevision;

    bool sessionIsCurrent() =>
        _host.connection.baseUrl == baseUrl &&
        _host.connection.token == token &&
        _host.connection.sessionRevision == revision;

    _resettingUserPassword = true;

    try {
      await _host.connection.changeOwnPassword(currentPassword: currentPassword, newPassword: newPassword);

      if (!sessionIsCurrent()) {
        throw PasswordChangeException(
          'Your server session changed. Return to settings before resetting your password.',
        );
      }
    } on PasswordChangeException catch (error) {
      if (error.requiresSignIn && sessionIsCurrent()) {
        await _signOutAfterPasswordReset();
      }

      rethrow;
    } finally {
      _resettingUserPassword = false;
    }
  }

  Future<AuthCredentials?> loadSavedCredentials() async {
    if (_savedCredentialsInvalidated) {
      return null;
    }

    if (_savedCredentials != null) {
      return _savedCredentials;
    }

    final credentials = await _host._authStorage.read();

    if (_savedCredentialsInvalidated) {
      return null;
    }

    _savedCredentials = credentials;

    return credentials;
  }

  Future<void> restoreSession() async {
    if (_restoringSession || _authState.isAuthorized) {
      return;
    }

    _restoringSession = true;
    final revision = _sessionRestores.advance();

    _setSessionStatus(SessionStatus.checking, error: null);

    try {
      await _restoreSessionInternal(revision).timeout(AppController.storedSessionRestoreTimeout);
    } on TimeoutException {
      if (_isRestoreSessionCurrent(revision)) {
        _host._pushMessage(
          'Auto-login timed out after ${AppController.storedSessionRestoreTimeout.inSeconds}s.',
          level: LogLevel.warning,
        );
        _setSessionStatus(SessionStatus.serverUnavailable, error: 'Saved server unavailable');
      }
    } finally {
      if (_isRestoreSessionCurrent(revision)) {
        _restoringSession = false;
      }
    }
  }

  Future<void> startFreshLoginFlow() async {
    _sessionRestores.advance();
    _restoringSession = false;
    await _host.logout(clearSaved: true);
    _host.connection.setBaseUrl(_host._initialBaseUrl);
    _setAuthorized(false, error: null);
  }

  Future<void> requireSignIn({String reason = 'Server keys changed. Sign in again to verify the new server key.'}) =>
      _signOutAfterPasswordReset(reason: reason, requiresSignIn: true);

  Future<void> _signOutAfterPasswordReset({String? reason, bool requiresSignIn = false}) async {
    // Invalidate restoration before the first await. An expired/revoked session
    // cannot authorize logout, so there is no additional request to send.
    _sessionRestores.advance();
    _restoringSession = false;

    final serverBaseUrl = _host.connection.baseUrl;

    _host.connection.setToken(null);
    final disconnectedRevision = _host.connection.sessionRevision;
    final clearSaved = _clearSavedCredentials();

    if (_host._disposed) {
      await clearSaved;

      return;
    }

    final preserveLocalPlayback = _host._playbackState.isLocalPlayback && _host._playbackState.track != null;

    _host._stopMetadataEventListener();
    _pauseDownloadsForDisconnectedServer(serverBaseUrl);
    _host._serverHealthFailureCount = 0;
    _host._serverReconnectAttempt = 0;
    _setSessionStatus(SessionStatus.offline, error: reason, requiresSignIn: requiresSignIn);
    _host._quicPort = null;

    if (preserveLocalPlayback) {
      _host._closeStreamControl();
    } else {
      _clearPlaybackForServerDisconnect();
    }

    await _host._detachListeningAccount(expectedSessionRevision: disconnectedRevision);
    await clearSaved;
  }

  void _beginBestEffortServerLogout() {
    if (_host.connection.token?.isNotEmpty != true) {
      return;
    }

    Future<void> requestServerLogout() async {
      try {
        await _host.connection.logout(timeout: AppController._serverLogoutBestEffortTimeout);
      } catch (err) {
        AppLogger.debug('Server logout skipped after local disconnect: $err');
      }
    }

    unawaited(requestServerLogout());
  }

  void _pauseDownloadsForDisconnectedServer(String serverBaseUrl) {
    Future<void> pauseServerDownloads() async {
      try {
        await _host._offlineDownloadManager.pauseDownloadsForServer(serverBaseUrl);
      } catch (err) {
        if (_host._disposed) {
          return;
        }

        _host._pushMessage('Failed to pause server downloads after disconnect: $err', level: LogLevel.warning);
      }
    }

    unawaited(pauseServerDownloads());
  }

  void _clearPlaybackForServerDisconnect() {
    _host._resetTrackTransitionState();
    _host._audioEngine.stop();

    _host._playQueue = <Track>[];
    _host._playIndex = 0;
    _host._queueShuffleMode = ShuffleMode.off;
    _host._queueShuffleScope = null;
    _host._queueShuffleArtistId = null;
    _host._queueShuffleAlbumId = null;
    _host._queueShufflePlaylistId = null;
    _host._offlineQueueSource = OfflineQueueSource.none;

    _host._lastStartPlaybackAt = null;
    _host._lastStartPlaybackTrackId = null;
    _host._lastStartPlaybackOffsetMs = null;
    _host._audioOutputStarted = false;

    _host._updatePlayback(
      track: null,
      isPlaying: false,
      isLoading: false,
      position: Duration.zero,
      duration: Duration.zero,
      bufferRatio: 0.0,
      bitrateKbps: null,
      streamConnected: false,
      streamRttMs: null,
      isLocalPlayback: false,
      queueSource: PlaybackQueueSource.none,
      queueSourcePlaylistId: null,
      localPlaybackSource: LocalPlaybackSource.none,
    );

    _host._clearNowPlaying();
  }

  bool _isRestoreSessionCurrent(int revision) {
    return !_host._disposed && _sessionRestores.isCurrent(revision);
  }

  Future<void> _restoreSessionInternal(int revision) async {
    final credentials = await _host.loadSavedCredentials();

    if (!_isRestoreSessionCurrent(revision) || credentials == null) {
      if (_isRestoreSessionCurrent(revision)) {
        _setSessionStatus(SessionStatus.offline, error: null);
      }

      return;
    }

    _host.connection.setBaseUrl(credentials.baseUrl);

    if (credentials.token.trim().isEmpty) {
      await _clearSavedCredentials();
      _host.connection.setToken(null);
      _setSessionStatus(SessionStatus.offline, error: null);

      return;
    }

    _host.connection.setTrust(credentials.trust);
    _host.connection.setToken(credentials.token);

    if (_host._listeningStats.storageError == null && credentials.serverId != null && credentials.userId != null) {
      _host._statsServerId = credentials.serverId;
      _host._statsUserId = credentials.userId;
      await _host._listeningStats.setAccount(serverId: credentials.serverId, userId: credentials.userId);

      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }

      await _host._refreshLocalStats();
    }

    try {
      final settings = await _host.connection.fetchPlaybackSettings(
        timeout: AppController._storedSessionRequestTimeout,
        retryable: false,
      );

      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }

      _host._updatePlayback(repeatMode: _host._parseRepeatMode(settings.repeatMode));
      _host._serverHealthFailureCount = 0;
      _setAuthorized(true, error: null);
      unawaited(_host._offlineDownloadManager.resumePausedForCurrentServer());
      unawaited(_host._offlineDownloadManager.repairOfflineMetadataFragments());
      unawaited(_host._refreshServerPorts(timeout: AppController._storedSessionRequestTimeout, retryable: false));
    } on ApiException catch (err) {
      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }

      _host._pushMessage('Auto-login failed: ${_host._formatApiError(err)}');

      if (err.statusCode == 401) {
        await requireSignIn(reason: 'Saved login expired. Sign in again.');
      } else {
        _setSessionStatus(SessionStatus.serverUnavailable, error: 'Saved server unavailable');
      }
    } catch (err) {
      if (!_isRestoreSessionCurrent(revision)) {
        return;
      }

      final identityChanged = await _host.connection.hasServerIdentityChanged();
      if (!_isRestoreSessionCurrent(revision)) return;
      if (identityChanged) {
        await requireSignIn();
        return;
      }

      _host._pushMessage('Auto-login failed: $err');
      _setSessionStatus(SessionStatus.serverUnavailable, error: 'Saved server unavailable');
    }
  }

  Future<void> _storeSavedCredentials(AuthCredentials credentials) async {
    _savedCredentialsInvalidated = false;
    _savedCredentials = credentials;
    await _queueSavedCredentialsWrite(() => _host._authStorage.write(credentials));
  }

  Future<void> _clearSavedCredentials() async {
    _savedCredentialsInvalidated = true;
    _savedCredentials = null;
    await _queueSavedCredentialsWrite(_host._authStorage.clear);
  }

  Future<void> _queueSavedCredentialsWrite(Future<void> Function() operation) {
    // A newly remembered session must be written after an earlier sign-out's
    // deletion, even when the platform secure storage operations finish late.
    final pending = _savedCredentialsWriteChain.catchError((Object _) {}).then((_) => operation());

    _savedCredentialsWriteChain = pending;

    return pending;
  }

  void _setAuthorized(bool authorized, {String? error}) {
    _setSessionStatus(authorized ? SessionStatus.authenticated : SessionStatus.offline, error: error);
  }

  void _setSessionStatus(SessionStatus status, {String? error, bool? isReconnecting, bool requiresSignIn = false}) {
    if (_host._disposed) {
      return;
    }

    if (_artistListSessionRevision != _host.connection.sessionRevision) {
      _artistListSessionRevision = _host.connection.sessionRevision;
      _host._invalidateArtistPages();
      _host._invalidateArtistReleases();
      _host._artists = [];
      _host._albums = [];
      _host._artistReleases = const ArtistReleases();
      _host._artistsOffset = 0;
      _host._artistsHasMore = true;
      _host._lastArtistId = null;
      _host._artistReleasesArtistId = null;
      _host._artistsController.add(const []);
      _host._albumsController.add(const []);
      _host._artistReleasesController.add(_host._artistReleases);
    }

    _authState = _authState.copyWith(
      status: status,
      baseUrl: _host.connection.baseUrl,
      error: error,
      isReconnecting: isReconnecting,
      requiresSignIn: requiresSignIn,
    );
    _authController.add(_authState);
    _host._notifyCarPlayAuthState(_authState.isAuthorized);

    if (_authState.isAuthorized) {
      _host._startMetadataEventListener();
      unawaited(_host._listeningSync?.sync(immediate: true) ?? Future<void>.value());
    } else {
      _host._stopMetadataEventListener();
    }

    _host._syncServerReconnectLoop();
  }

  bool _requireServer(String action) {
    if (_authState.isAuthorized) {
      return true;
    }

    if (_authState.status == SessionStatus.serverUnavailable) {
      _host._pushMessage(
        'Server is unavailable before $action. Reconnecting in the background.',
        level: LogLevel.warning,
      );
      unawaited(_host._triggerImmediateServerReconnect(reason: 'server action'));

      return false;
    }

    _host._pushMessage('Connect to a server before $action.', level: LogLevel.warning);

    return false;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _SessionFacade {
  _SessionCoordinator get _sessionCoordinator;

  AuthCredentials? get _savedCredentials => _sessionCoordinator._savedCredentials;

  RequestGeneration get _sessionRestores => _sessionCoordinator._sessionRestores;

  StreamController<AuthState> get _authController => _sessionCoordinator._authController;

  AuthState get _authState => _sessionCoordinator._authState;

  set _authState(AuthState value) => _sessionCoordinator._authState = value;

  Stream<AuthState> get authStream => _sessionCoordinator.authStream;

  AuthState get authState => _sessionCoordinator.authState;

  bool get hasSavedCredentials => _sessionCoordinator.hasSavedCredentials;

  String? get savedUsername => _sessionCoordinator.savedUsername;

  String? get savedBaseUrl => _sessionCoordinator.savedBaseUrl;

  bool get canUseServer => _sessionCoordinator.canUseServer;

  bool get canResetUserPassword => _sessionCoordinator.canResetUserPassword;

  bool get _canAttemptRemotePlayback => _sessionCoordinator._canAttemptRemotePlayback;

  bool get _shouldAutoReconnectServer => _sessionCoordinator._shouldAutoReconnectServer;

  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) => _sessionCoordinator.loginWithPassword(
    baseUrl: baseUrl,
    username: username,
    password: password,
    rememberMe: rememberMe,
  );

  void loginWithToken({required String baseUrl, required String token}) =>
      _sessionCoordinator.loginWithToken(baseUrl: baseUrl, token: token);

  Future<bool> probeServer(String input) => _sessionCoordinator.probeServer(input);

  Future<void> logout({bool clearSaved = true}) => _sessionCoordinator.logout(clearSaved: clearSaved);

  Future<void> resetUserPassword({required String currentPassword, required String newPassword}) =>
      _sessionCoordinator.resetUserPassword(currentPassword: currentPassword, newPassword: newPassword);

  Future<AuthCredentials?> loadSavedCredentials() => _sessionCoordinator.loadSavedCredentials();

  Future<void> restoreSession() => _sessionCoordinator.restoreSession();

  Future<void> startFreshLoginFlow() => _sessionCoordinator.startFreshLoginFlow();

  Future<void> _storeSavedCredentials(AuthCredentials credentials) =>
      _sessionCoordinator._storeSavedCredentials(credentials);

  void _setSessionStatus(SessionStatus status, {String? error, bool? isReconnecting}) =>
      _sessionCoordinator._setSessionStatus(status, error: error, isReconnecting: isReconnecting);

  bool _requireServer(String action) => _sessionCoordinator._requireServer(action);
}
