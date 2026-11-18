class ApiException implements Exception {
  final int statusCode;
  final String body;
  final Duration? retryAfter;

  ApiException(this.statusCode, this.body, {this.retryAfter});

  @override
  String toString() => 'ApiException($statusCode): $body';
}
