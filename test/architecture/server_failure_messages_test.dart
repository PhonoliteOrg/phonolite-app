import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/auth/server_failure_messages.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

void main() {
  test('typed connection failures retain application messages and safe probe details', () {
    final cases = <ServerConnectionFailure, String>{
      ServerConnectionFailure.missingAddress: 'Exception: Server URL is required',
      ServerConnectionFailure.invalidAddress: 'Exception: Enter the server IP and HTTPS port',
      ServerConnectionFailure.timedOut: 'Connection timed out. Check the server address and port.',
    };

    for (final entry in cases.entries) {
      expect(serverFailureMessage(ServerConnectionCheckException.forReason(entry.key)), entry.value);
    }

    expect(
      serverFailureMessage(
        ServerConnectionCheckException.forReason(ServerConnectionFailure.connectionFailed, detail: 'Pin mismatch'),
      ),
      'Pin mismatch',
    );
    expect(serverFailureMessage(ServerConnectionCheckException('Adapter failure')), 'Adapter failure');
  });

  test('password failures retain their established safe instructions', () {
    final cases = <PasswordChangeFailure, String>{
      PasswordChangeFailure.notAuthenticated: 'Connect to your authenticated server before resetting your password.',
      PasswordChangeFailure.invalidCurrentPassword: 'Enter your current password.',
      PasswordChangeFailure.missingNewPassword: 'Enter your new password.',
      PasswordChangeFailure.newPasswordTooLong: 'Your new password is too long.',
      PasswordChangeFailure.sessionChanged:
          'Your server session changed. Return to settings before resetting your password.',
      PasswordChangeFailure.unconfirmed:
          'The password change could not be confirmed. Check your connection and password before trying again.',
      PasswordChangeFailure.rejected: 'The server rejected the password change.',
      PasswordChangeFailure.sessionExpired: 'Your session has expired. Sign in again before resetting your password.',
      PasswordChangeFailure.incorrectCurrentPassword: 'Your current password is incorrect.',
      PasswordChangeFailure.rateLimited: 'Too many password reset attempts. Wait a few minutes and try again.',
    };

    for (final entry in cases.entries) {
      expect(serverFailureMessage(PasswordChangeException.forReason(entry.key)), entry.value);
    }

    expect(serverFailureMessage(PasswordChangeException('Adapter failure')), 'Adapter failure');
  });
}
