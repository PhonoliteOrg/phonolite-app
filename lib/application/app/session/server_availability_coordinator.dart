part of 'package:phonolite_app/application/app/app_controller.dart';

class _ServerAvailabilityCoordinator {
  final AppController _host;
  Timer? _healthTimer;
  Timer? _serverReconnectTimer;
  Future<void>? _serverAvailabilityFuture;
  bool _healthPingInFlight = false;
  bool _appInForeground = true;
  bool _lastConnectivityAvailable = true;
  int _serverHealthFailureCount = 0;
  int _serverReconnectAttempt = 0;
  int? _quicPort;
  final Random _reconnectRandom = Random();
  StreamSubscription<bool>? _connectivitySubscription;

  _ServerAvailabilityCoordinator(this._host);

  Future<void> retryServerConnection() async {
    _host._pushMessage('Retrying server connection...');
    await _triggerImmediateServerReconnect(reason: 'manual retry');
  }

  Future<void> refreshServerAvailability() async {
    await _refreshServerAvailability();
  }

  void _configureConnectivitySignals() {
    _connectivitySubscription = _host._connectivitySignalSource.availabilityStream.listen(
      _handleConnectivityAvailabilityChanged,
      onError: (Object error) {
        _host._pushMessage('Network change monitor failed: $error', level: LogLevel.warning);
      },
    );

    void handleInitialConnectivity(bool available) {
      if (_host._disposed) {
        return;
      }

      _lastConnectivityAvailable = available;

      if (available && _host._authState.status == SessionStatus.serverUnavailable) {
        unawaited(_triggerImmediateServerReconnect(reason: 'network available'));
      }
    }

    unawaited(_host._connectivitySignalSource.hasConnectivity().then(handleInitialConnectivity).catchError((_) {}));
  }

  void _handleConnectivityAvailabilityChanged(bool available) {
    if (_host._disposed) {
      return;
    }

    final wasAvailable = _lastConnectivityAvailable;

    _lastConnectivityAvailable = available;

    if (available && !wasAvailable) {
      unawaited(_triggerImmediateServerReconnect(reason: 'network restored'));
    }
  }

  void _syncServerReconnectLoop() {
    if (_host._disposed) {
      _stopServerReconnectLoop(resetAttempts: true);

      return;
    }

    if (_host._shouldAutoReconnectServer) {
      _scheduleServerReconnect();
    } else {
      _stopServerReconnectLoop(resetAttempts: true);
    }
  }

  void _stopServerReconnectLoop({required bool resetAttempts}) {
    _serverReconnectTimer?.cancel();
    _serverReconnectTimer = null;

    if (resetAttempts) {
      _serverReconnectAttempt = 0;
    }
  }

  void _scheduleServerReconnect() {
    if (!_host._shouldAutoReconnectServer || _serverReconnectTimer != null || _serverAvailabilityFuture != null) {
      return;
    }

    final delay = _serverReconnectDelayForAttempt(_serverReconnectAttempt);

    void reconnectWhenDue() {
      _serverReconnectTimer = null;
      unawaited(_refreshServerAvailability(reconnectAttempt: true));
    }

    _serverReconnectTimer = Timer(delay, reconnectWhenDue);
  }

  Duration _serverReconnectDelayForAttempt(int attempt) {
    final backoff = _appInForeground
        ? AppController._serverReconnectForegroundBackoff
        : AppController._serverReconnectBackgroundBackoff;
    final base = backoff[min(attempt, backoff.length - 1)];
    final jitterMs = AppController._serverReconnectJitterMax.inMilliseconds <= 0
        ? 0
        : _reconnectRandom.nextInt(AppController._serverReconnectJitterMax.inMilliseconds + 1);

    return base + Duration(milliseconds: jitterMs);
  }

  Future<void> _triggerImmediateServerReconnect({required String reason}) {
    assert(reason.isNotEmpty);

    if (!_host._shouldAutoReconnectServer) {
      _syncServerReconnectLoop();

      return Future<void>.value();
    }

    _serverReconnectTimer?.cancel();
    _serverReconnectTimer = null;

    return _refreshServerAvailability(reconnectAttempt: true);
  }

  void _setServerReconnecting(bool value) {
    if (_host._disposed) {
      return;
    }

    if (_host._authState.status != SessionStatus.serverUnavailable || _host._authState.isReconnecting == value) {
      return;
    }

    _host._authState = _host._authState.copyWith(
      baseUrl: _host.connection.baseUrl,
      error: _host._authState.error,
      isReconnecting: value,
    );
    _host._authController.add(_host._authState);
    _host._notifyCarPlayAuthState(_host._authState.isAuthorized);
  }

  void _handleApiError(ApiException err, {required String context}) {
    if (err.statusCode == 401) {
      unawaited(_host._sessionCoordinator.requireSignIn(reason: 'Your session has ended. Sign in again.'));
      _host._pushMessage('Unauthorized. Please log in.');

      return;
    }

    final message = _host._formatApiError(err);

    _host._pushMessage('Failed to load $context: $message', level: LogLevel.warning);
  }

  Future<void> _handleReconnectUnauthorized() async {
    await _host._sessionCoordinator.requireSignIn(reason: 'Saved login expired. Sign in again.');
    _host._pushMessage('Saved login expired. Please log in.');
  }

  void _handleServerTransportFailure(Object error) {
    if (!_host._canAttemptRemotePlayback) {
      return;
    }

    _recordServerAvailabilityFailure(error: 'Server unavailable: $error', reconnectAttempt: false);
  }

  void _markServerUnavailable({required String error}) {
    if (!_host._canAttemptRemotePlayback) {
      return;
    }

    _serverHealthFailureCount = max(_serverHealthFailureCount, AppController._serverUnavailableHealthFailureThreshold);
    _serverReconnectAttempt = 0;
    _quicPort = null;
    unawaited(_host._offlineDownloadManager.pauseDownloadsForServer(_host.connection.baseUrl));
    _host._setSessionStatus(SessionStatus.serverUnavailable, error: error);
    _host._pushMessage(error, level: LogLevel.warning);
  }

  void _restoreServerAvailability({int? rttMs}) {
    if (_host._disposed) {
      return;
    }

    if (_host._authState.status != SessionStatus.serverUnavailable) {
      return;
    }

    final token = _host.connection.token;

    if (token == null || token.isEmpty) {
      _host._setSessionStatus(SessionStatus.offline, error: null);

      return;
    }

    _serverHealthFailureCount = 0;
    _host._setSessionStatus(SessionStatus.authenticated, error: null);

    if (!_host._audioEngine.hasActivePlayer) {
      _host._updatePlayback(streamConnected: true, streamRttMs: rttMs);
    }

    _host._pushMessage('Server connection restored.');
    unawaited(_refreshServerPorts(timeout: const Duration(seconds: 4)));
    unawaited(_host._loadPlaybackSettings());
    unawaited(_host._offlineDownloadManager.resumePausedForCurrentServer());
    unawaited(_host._offlineDownloadManager.repairOfflineMetadataFragments());
    _host._retryPlaybackAfterServerReconnect();
  }

  Future<void> _refreshServerPorts({Duration timeout = const Duration(seconds: 8), bool retryable = true}) async {
    try {
      final ports = await _host.connection.fetchServerPorts(timeout: timeout, retryable: retryable);

      if (ports.quicEnabled && (ports.quicPort ?? 0) > 0) {
        _quicPort = ports.quicPort;
      } else {
        _quicPort = null;
      }
    } catch (err) {
      _quicPort = null;
      _host._pushMessage('Failed to load server ports: $err', level: LogLevel.warning);
    }
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pollHealth());
    _pollHealth();
  }

  Future<void> _refreshServerAvailability({bool reconnectAttempt = false}) async {
    final active = _serverAvailabilityFuture;

    if (active != null) {
      if (reconnectAttempt) {
        _setServerReconnecting(true);
      }

      return active;
    }

    final future = _runServerAvailabilityRefresh(reconnectAttempt: reconnectAttempt);

    void finishAvailabilityRefresh() {
      _serverAvailabilityFuture = null;

      if (!_host._disposed) {
        _syncServerReconnectLoop();
      }
    }

    _serverAvailabilityFuture = future.whenComplete(finishAvailabilityRefresh);

    return _serverAvailabilityFuture!;
  }

  Future<void> _runServerAvailabilityRefresh({required bool reconnectAttempt}) async {
    if (_healthPingInFlight) {
      return;
    }

    _healthPingInFlight = true;
    final revision = _host.connection.sessionRevision;
    final baseUrl = _host.connection.baseUrl;
    final token = _host.connection.token;
    bool isCurrent() =>
        !_host._disposed &&
        _host.connection.sessionRevision == revision &&
        _host.connection.baseUrl == baseUrl &&
        _host.connection.token == token;

    if (reconnectAttempt) {
      _setServerReconnecting(true);
    }

    try {
      final rttMs = await _host.connection.pingHealthMs(timeout: const Duration(seconds: 4));

      if (!isCurrent()) {
        return;
      }

      if (rttMs == null && token?.isNotEmpty == true) {
        final identityChanged = await _host.connection.hasServerIdentityChanged();
        if (!isCurrent()) return;
        if (identityChanged) {
          await _host._sessionCoordinator.requireSignIn();
          return;
        }
      }

      if (_host._authState.status == SessionStatus.serverUnavailable) {
        if (rttMs == null) {
          _recordServerAvailabilityFailure(
            error: _host._authState.error ?? 'Server unavailable',
            reconnectAttempt: reconnectAttempt,
          );

          return;
        }

        await _host.connection.fetchCapabilities();
        if (!isCurrent()) return;
        _serverHealthFailureCount = 0;
        _serverReconnectAttempt = 0;
        _restoreServerAvailability(rttMs: rttMs);

        return;
      }

      if (rttMs != null) {
        _serverHealthFailureCount = 0;

        if (!_host._audioEngine.hasActivePlayer) {
          _host._updatePlayback(streamConnected: true, streamRttMs: rttMs);
        }

        _host._retryPlaybackAfterServerReconnect();

        return;
      }

      _recordServerAvailabilityFailure(error: 'Server unavailable', reconnectAttempt: false);
    } on ApiException catch (err) {
      if (!isCurrent()) return;
      if (err.statusCode == 401) {
        await _handleReconnectUnauthorized();
      } else {
        _recordServerAvailabilityFailure(
          error: 'Server unavailable: ${_host._formatApiError(err)}',
          reconnectAttempt: reconnectAttempt,
        );
      }
    } catch (err) {
      if (!isCurrent()) return;
      _recordServerAvailabilityFailure(error: 'Server unavailable: $err', reconnectAttempt: reconnectAttempt);
    } finally {
      _healthPingInFlight = false;

      if (_host._authState.status == SessionStatus.serverUnavailable && _host._authState.isReconnecting) {
        _setServerReconnecting(false);
      }
    }
  }

  void _recordServerAvailabilityFailure({required String error, required bool reconnectAttempt}) {
    if (_host._disposed) {
      return;
    }

    _serverHealthFailureCount++;

    if (_host._hasActiveRemotePlayback) {
      return;
    }

    if (!_host._audioEngine.hasActivePlayer) {
      _host._updatePlayback(streamConnected: false, streamRttMs: null);
    }

    if (_host._authState.status == SessionStatus.serverUnavailable) {
      if (reconnectAttempt) {
        _serverReconnectAttempt++;
      }

      _host._setSessionStatus(SessionStatus.serverUnavailable, error: error, isReconnecting: false);

      return;
    }

    if (_host._authState.isAuthorized &&
        _serverHealthFailureCount >= AppController._serverUnavailableHealthFailureThreshold) {
      _markServerUnavailable(error: 'Server unavailable');
    }
  }

  Future<void> _pollHealth() =>
      _refreshServerAvailability(reconnectAttempt: _host._authState.status == SessionStatus.serverUnavailable);
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _ServerAvailabilityFacade {
  _ServerAvailabilityCoordinator get _availabilityCoordinator;

  Timer? get _healthTimer => _availabilityCoordinator._healthTimer;

  set _healthTimer(Timer? value) => _availabilityCoordinator._healthTimer = value;

  Timer? get _serverReconnectTimer => _availabilityCoordinator._serverReconnectTimer;

  set _serverReconnectTimer(Timer? value) => _availabilityCoordinator._serverReconnectTimer = value;

  bool get _appInForeground => _availabilityCoordinator._appInForeground;

  set _appInForeground(bool value) => _availabilityCoordinator._appInForeground = value;

  set _serverHealthFailureCount(int value) => _availabilityCoordinator._serverHealthFailureCount = value;

  set _serverReconnectAttempt(int value) => _availabilityCoordinator._serverReconnectAttempt = value;

  int? get _quicPort => _availabilityCoordinator._quicPort;

  set _quicPort(int? value) => _availabilityCoordinator._quicPort = value;

  StreamSubscription<bool>? get _connectivitySubscription => _availabilityCoordinator._connectivitySubscription;

  Future<void> retryServerConnection() => _availabilityCoordinator.retryServerConnection();

  Future<void> refreshServerAvailability() => _availabilityCoordinator.refreshServerAvailability();

  void _configureConnectivitySignals() => _availabilityCoordinator._configureConnectivitySignals();

  void _syncServerReconnectLoop() => _availabilityCoordinator._syncServerReconnectLoop();

  void _stopServerReconnectLoop({required bool resetAttempts}) =>
      _availabilityCoordinator._stopServerReconnectLoop(resetAttempts: resetAttempts);

  void _scheduleServerReconnect() => _availabilityCoordinator._scheduleServerReconnect();

  Future<void> _triggerImmediateServerReconnect({required String reason}) =>
      _availabilityCoordinator._triggerImmediateServerReconnect(reason: reason);

  void _handleApiError(ApiException err, {required String context}) =>
      _availabilityCoordinator._handleApiError(err, context: context);

  void _handleServerTransportFailure(Object error) => _availabilityCoordinator._handleServerTransportFailure(error);

  Future<void> _refreshServerPorts({Duration timeout = const Duration(seconds: 8), bool retryable = true}) =>
      _availabilityCoordinator._refreshServerPorts(timeout: timeout, retryable: retryable);

  void _startHealthMonitor() => _availabilityCoordinator._startHealthMonitor();

  Future<void> _refreshServerAvailability({bool reconnectAttempt = false}) =>
      _availabilityCoordinator._refreshServerAvailability(reconnectAttempt: reconnectAttempt);
}
