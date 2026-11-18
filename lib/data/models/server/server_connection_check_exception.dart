enum ServerConnectionFailure { missingAddress, invalidAddress, timedOut, connectionFailed, identityChanged }

class ServerConnectionCheckException implements Exception {
  final String message;
  final ServerConnectionFailure? reason;

  /// An application-provided message, retained for existing adapters.
  ServerConnectionCheckException(this.message) : reason = null;

  /// Technical failures carry a reason; application code owns display text.
  ServerConnectionCheckException.forReason(ServerConnectionFailure this.reason, {String? detail})
    : message = detail ?? 'Server connection failed: ${reason.name}';

  @override
  String toString() => message;
}
