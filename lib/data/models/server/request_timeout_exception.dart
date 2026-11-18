class RequestTimeoutException implements Exception {
  final Duration timeout;

  RequestTimeoutException(this.timeout);

  @override
  String toString() => 'Request timed out after ${timeout.inSeconds}s';
}
