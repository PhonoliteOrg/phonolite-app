const Object _authUnset = Object();

enum SessionStatus { offline, checking, serverReachable, serverUnavailable, authenticated }

class AuthState {
  final SessionStatus status;
  final String baseUrl;
  final String? error;
  final bool isReconnecting;
  final bool requiresSignIn;

  AuthState({
    required this.baseUrl,
    bool? isAuthorized,
    SessionStatus? status,
    this.error,
    this.isReconnecting = false,
    this.requiresSignIn = false,
  }) : status = status ?? (isAuthorized == true ? SessionStatus.authenticated : SessionStatus.offline);

  bool get isAuthorized => status == SessionStatus.authenticated;

  bool get hasSession => switch (status) {
    SessionStatus.authenticated || SessionStatus.serverUnavailable => true,
    SessionStatus.offline || SessionStatus.checking || SessionStatus.serverReachable => false,
  };

  /// Omitted [error] keeps its value; explicit `null` clears it.
  AuthState copyWith({
    bool? isAuthorized,
    SessionStatus? status,
    String? baseUrl,
    Object? error = _authUnset,
    bool? isReconnecting,
    bool? requiresSignIn,
  }) {
    final SessionStatus nextStatus;

    if (status != null) {
      nextStatus = status;
    } else if (isAuthorized == null) {
      nextStatus = this.status;
    } else {
      nextStatus = isAuthorized ? SessionStatus.authenticated : SessionStatus.offline;
    }

    return AuthState(
      status: nextStatus,
      baseUrl: baseUrl ?? this.baseUrl,
      error: identical(error, _authUnset) ? this.error : error as String?,
      isReconnecting: nextStatus == SessionStatus.serverUnavailable ? isReconnecting ?? this.isReconnecting : false,
      requiresSignIn: requiresSignIn ?? this.requiresSignIn,
    );
  }
}
