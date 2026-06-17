enum SessionStatus {
  offline,
  checking,
  serverReachable,
  serverUnavailable,
  authenticated,
}

class AuthState {
  AuthState({
    bool? isAuthorized,
    SessionStatus? status,
    required this.baseUrl,
    this.error,
    this.isReconnecting = false,
  }) : status =
           status ??
           (isAuthorized == true
               ? SessionStatus.authenticated
               : SessionStatus.offline);

  final SessionStatus status;
  final String baseUrl;
  final String? error;
  final bool isReconnecting;

  bool get isAuthorized => status == SessionStatus.authenticated;
  bool get hasSession =>
      status == SessionStatus.authenticated ||
      status == SessionStatus.serverUnavailable;

  AuthState copyWith({
    bool? isAuthorized,
    SessionStatus? status,
    String? baseUrl,
    String? error,
    bool? isReconnecting,
  }) {
    final nextStatus =
        status ??
        (isAuthorized == null
            ? this.status
            : isAuthorized
            ? SessionStatus.authenticated
            : SessionStatus.offline);
    return AuthState(
      status: nextStatus,
      baseUrl: baseUrl ?? this.baseUrl,
      error: error,
      isReconnecting: nextStatus == SessionStatus.serverUnavailable
          ? isReconnecting ?? this.isReconnecting
          : false,
    );
  }
}
