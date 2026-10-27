import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class AccountSessionsController extends FeatureController {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  bool get busy => _busy;

  String? get message => _message;

  bool get failed => _failed;

  Future<void> signOutOtherDevices(Future<int> Function() action, {required bool Function() sessionIsCurrent}) async {
    await _revoke(() async {
      final count = await action();

      return count == 0
          ? 'No other app sessions were signed in.'
          : 'Signed out $count other app ${count == 1 ? 'session' : 'sessions'}. This device stays signed in.';
    }, sessionIsCurrent: sessionIsCurrent);
  }

  Future<void> signOutAllDevices(Future<void> Function() action, {required bool Function() sessionIsCurrent}) async {
    await _revoke(() async {
      await action();

      return 'Signed out all app sessions. Admin console sessions stay signed in.';
    }, sessionIsCurrent: sessionIsCurrent);
  }

  Future<void> _revoke(Future<String> Function() action, {required bool Function() sessionIsCurrent}) async {
    if (isDisposed || _busy || !sessionIsCurrent()) {
      return;
    }

    update(() {
      _busy = true;
      _message = null;
      _failed = false;
    });

    try {
      final message = await action();

      if (!isDisposed && sessionIsCurrent()) {
        update(() => _message = message);
      }
    } catch (error) {
      if (!isDisposed && sessionIsCurrent()) {
        update(() {
          _message = _failureMessage(error);
          _failed = true;
        });

        // Server response bodies and transport details can contain private data.
        AppLogger.warning('Could not confirm account session revocation (${error.runtimeType}).');
      }
    } finally {
      update(() => _busy = false);
    }
  }

  String _failureMessage(Object error) {
    if (error is ApiException) {
      return switch (error.statusCode) {
        401 => 'Your session has expired. Sign in again to manage devices.',
        403 => 'This account cannot manage device sessions on the server.',
        404 || 405 => 'This server needs an update to support signing out other devices.',
        429 => 'Too many requests. Wait a moment before trying again.',
        _ => 'Could not confirm the sign-out request. Check your connection before trying again.',
      };
    }

    return 'Could not confirm the sign-out request. Check your connection before trying again.';
  }
}
