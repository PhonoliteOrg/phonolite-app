part of '../app_controller.dart';

extension _SessionIdentity on _SessionCoordinator {
  void _publishSession() => _authController.add(_authState);

  Future<void> _acceptAccount(int revision, String userId, {String? serverId}) async {
    if (!_isServerSessionCurrent(revision) || userId.isEmpty) return;
    final previous = _authState.account;
    final account = SessionAccount(
      userId: userId,
      baseUrl: _host.connection.baseUrl,
      trust: _host.connection.trust,
      serverId: serverId ?? (previous?.userId == userId ? previous?.serverId : null),
    );
    if (account.storageScope != previous?.storageScope || account.serverId != previous?.serverId) {
      _authState = _authState.copyWith(account: account);
      _publishSession();
    }

    final saved = _savedCredentials;
    if (saved == null ||
        saved.baseUrl != _host.connection.baseUrl ||
        saved.token != _host.connection.token ||
        (saved.serverId == account.serverId && saved.userId == userId)) {
      return;
    }

    try {
      await _storeSavedCredentials(
        AuthCredentials(
          baseUrl: saved.baseUrl,
          token: saved.token,
          username: saved.username,
          trust: saved.trust,
          serverId: account.serverId,
          userId: userId,
        ),
      );
    } on Object catch (error) {
      _reportSavedCredentialsFailure('save the account identity on this device', error);
    }
  }

  void _restoreSavedPlayback(AuthCredentials saved) {
    final userId = saved.userId;
    if (userId == null || userId.isEmpty) return;
    final revision = _host.connection.sessionRevision;
    final scope = SessionAccount(userId: userId, baseUrl: saved.baseUrl, trust: saved.trust).storageScope;
    bool current() =>
        !_host._disposed &&
        _host.connection.sessionRevision == revision &&
        _authState.status == SessionStatus.serverUnavailable &&
        _authState.account?.storageScope == scope &&
        _host.connection.token == saved.token &&
        ServerTrust.origin(Uri.parse(_host.connection.baseUrl)) == ServerTrust.origin(Uri.parse(saved.baseUrl)) &&
        _host.connection.trust?.spki == saved.trust.spki &&
        _host.connection.trust?.opaqueKey == saved.trust.opaqueKey;
    unawaited(_host._resumeCoordinator.restoreSavedAccount(scope, sessionIsCurrent: current));
  }

  void _serverUnavailable(String error, {bool? isReconnecting}) =>
      _setSessionStatus(SessionStatus.serverUnavailable, error: error, isReconnecting: isReconnecting);

  bool _serverRecovered() {
    if (_host._disposed || _authState.status != SessionStatus.serverUnavailable) return false;
    final authorized = _canAttemptRemotePlayback;
    _setSessionStatus(authorized ? SessionStatus.authenticated : SessionStatus.offline, error: null);
    return authorized;
  }

  void _setServerReconnecting(bool value) {
    if (_host._disposed) {
      return;
    }

    if (_authState.status != SessionStatus.serverUnavailable || _authState.isReconnecting == value) {
      return;
    }

    _authState = _authState.copyWith(baseUrl: _host.connection.baseUrl, error: _authState.error, isReconnecting: value);
    _publishSession();
    _host._notifyCarPlayAuthState(_authState.isAuthorized);
  }
}
