import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Converts safe technical failures into the application's established text.
/// Unknown failures retain their existing diagnostic representation.
String serverFailureMessage(Object error) {
  if (error is PasswordChangeException) {
    return switch (error.reason) {
      null => error.message,
      PasswordChangeFailure.notAuthenticated => 'Connect to your authenticated server before resetting your password.',
      PasswordChangeFailure.invalidCurrentPassword => 'Enter your current password.',
      PasswordChangeFailure.missingNewPassword => 'Enter your new password.',
      PasswordChangeFailure.newPasswordTooLong => 'Your new password is too long.',
      PasswordChangeFailure.sessionChanged =>
        'Your server session changed. Return to settings before resetting your password.',
      PasswordChangeFailure.unconfirmed =>
        'The password change could not be confirmed. Check your connection and password before trying again.',
      PasswordChangeFailure.rejected => 'The server rejected the password change.',
      PasswordChangeFailure.sessionExpired => 'Your session has expired. Sign in again before resetting your password.',
      PasswordChangeFailure.incorrectCurrentPassword => 'Your current password is incorrect.',
      PasswordChangeFailure.rateLimited => 'Too many password reset attempts. Wait a few minutes and try again.',
    };
  }

  if (error is ServerConnectionCheckException) {
    return switch (error.reason) {
      null || ServerConnectionFailure.connectionFailed => error.message,
      ServerConnectionFailure.missingAddress => 'Exception: Server URL is required',
      ServerConnectionFailure.invalidAddress => 'Exception: Enter the server IP and HTTPS port',
      ServerConnectionFailure.timedOut => 'Connection timed out. Check the server address and port.',
      ServerConnectionFailure.identityChanged => 'Server keys changed. Sign in again to verify the new server key.',
    };
  }

  return error.toString();
}
