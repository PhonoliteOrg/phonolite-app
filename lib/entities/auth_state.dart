enum SessionStatus { offline, checking, serverReachable, authenticated }

class AuthState {
  AuthState({
    bool? isAuthorized,
    SessionStatus? status,
    required this.baseUrl,
    this.error,
  }) : status =
           status ??
           (isAuthorized == true
               ? SessionStatus.authenticated
               : SessionStatus.offline);

  final SessionStatus status;
  final String baseUrl;
  final String? error;

  bool get isAuthorized => status == SessionStatus.authenticated;

  AuthState copyWith({
    bool? isAuthorized,
    SessionStatus? status,
    String? baseUrl,
    String? error,
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
    );
  }
}
