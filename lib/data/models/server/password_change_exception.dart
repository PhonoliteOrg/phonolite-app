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
