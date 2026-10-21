import 'dart:convert';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/auth/server_failure_messages.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

class PasswordChangeController extends FeatureController {
  final AppController app;
  int _clearPasswordsRevision = 0;
  late final int _sessionRevision;
  bool _saving = false;
  bool _sessionChanged = false;
  bool _completed = false;
  String? _error;

  PasswordChangeController(this.app) {
    _sessionRevision = app.connection.sessionRevision;
    _sessionChanged = !_isCurrentSession;

    void handleSessionChanged(AuthState _) {
      if (isDisposed || saving || completed || _isCurrentSession) {
        return;
      }

      void markSessionChanged() {
        _clearPasswordsRevision++;
        _sessionChanged = true;
      }

      update(markSessionChanged);
    }

    listenTo(app.authStream, handleSessionChanged);
  }

  int get clearPasswordsRevision => _clearPasswordsRevision;

  bool get saving => _saving;

  bool get sessionChanged => _sessionChanged;

  bool get completed => _completed;

  String? get error => _error;

  bool get _isCurrentSession => app.authState.isAuthorized && app.connection.sessionRevision == _sessionRevision;

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    if (saving || completed) {
      return;
    }

    if (!_isCurrentSession) {
      _clearPasswordsRevision++;
      update(() => _sessionChanged = true);

      return;
    }

    final validationError = _validate(currentPassword, newPassword, confirmation);

    if (validationError != null) {
      update(() => _error = validationError);

      return;
    }

    void beginSubmission() {
      _saving = true;
      _error = null;
    }

    update(beginSubmission);

    try {
      await app.resetUserPassword(currentPassword: currentPassword, newPassword: newPassword);

      if (isDisposed) {
        return;
      }

      _clearPasswordsRevision++;
      update(() => _completed = true);
    } catch (error) {
      if (isDisposed) {
        return;
      }

      _clearPasswordsRevision++;

      void publishFailure() {
        _error = error is PasswordChangeException
            ? serverFailureMessage(error)
            : 'The password change could not be confirmed. Check your connection and password before trying again.';
        _sessionChanged = !_isCurrentSession || (error is PasswordChangeException && error.requiresSignIn);
      }

      update(publishFailure);
    } finally {
      if (!isDisposed) {
        update(() => _saving = false);
      }
    }
  }

  String? _validate(String currentPassword, String newPassword, String confirmation) {
    if (currentPassword.isEmpty) {
      return 'Enter your current password.';
    }

    if (utf8.encode(currentPassword).length > 1024) {
      return 'Your current password is too long.';
    }

    if (newPassword.isEmpty) {
      return 'Enter your new password.';
    }

    if (utf8.encode(newPassword).length > 1024) {
      return 'Your new password is too long.';
    }

    if (confirmation != newPassword) {
      return 'The new passwords do not match.';
    }

    return null;
  }
}
