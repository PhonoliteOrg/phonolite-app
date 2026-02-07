class AuthState {
  AuthState({
    required this.isAuthorized,
    required this.baseUrl,
    this.error,
  });

  final bool isAuthorized;
  final String baseUrl;
  final String? error;

  AuthState copyWith({bool? isAuthorized, String? baseUrl, String? error}) {
    return AuthState(
      isAuthorized: isAuthorized ?? this.isAuthorized,
      baseUrl: baseUrl ?? this.baseUrl,
      error: error,
    );
  }
}
