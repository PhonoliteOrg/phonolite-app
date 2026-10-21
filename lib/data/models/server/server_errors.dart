import 'dart:async';

typedef ServerReachabilityProbe =
    Future<void> Function({required String host, required int port, String? expectedSpki});

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class RequestTimeoutException implements Exception {
  final Duration timeout;

  RequestTimeoutException(this.timeout);

  @override
  String toString() => 'Request timed out after ${timeout.inSeconds}s';
}

enum ServerConnectionFailure { missingAddress, invalidAddress, timedOut, connectionFailed }

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

enum PasswordChangeFailure {
  notAuthenticated,
  invalidCurrentPassword,
  missingNewPassword,
  newPasswordTooLong,
  sessionChanged,
  unconfirmed,
  rejected,
  sessionExpired,
  incorrectCurrentPassword,
  rateLimited,
}

/// Safe failure details, without passwords, bearer tokens or response data.
/// Application code maps typed reasons to user-facing instructions.
class PasswordChangeException implements Exception {
  final String message;
  final PasswordChangeFailure? reason;
  final bool requiresSignIn;
  final int? statusCode;

  /// An application-provided message, retained for existing adapters.
  PasswordChangeException(this.message, {this.requiresSignIn = false, this.statusCode}) : reason = null;

  PasswordChangeException.forReason(PasswordChangeFailure this.reason, {this.requiresSignIn = false, this.statusCode})
    : message = 'Password change failed: ${reason.name}';

  @override
  String toString() => message;
}
