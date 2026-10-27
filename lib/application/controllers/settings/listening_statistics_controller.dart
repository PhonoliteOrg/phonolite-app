import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

class ListeningStatisticsController extends FeatureController {
  int _pendingChanges = 0;
  bool _resetting = false;

  bool get saving => _pendingChanges > 0;

  bool get resetting => _resetting;

  Future<void> change(bool enabled, Future<void> Function(bool) save) async {
    if (isDisposed || _resetting) {
      return;
    }

    // The service applies consent immediately and owns serialized persistence.
    update(() => _pendingChanges++);

    try {
      await save(enabled);
    } catch (error) {
      AppLogger.warning('Could not save the statistics setting: $error');
    } finally {
      update(() => _pendingChanges--);
    }
  }

  static Future<void> resetForSession(
    AppController app, {
    required bool serverConnected,
    required int sessionRevision,
  }) async {
    if (app.authState.isAuthorized != serverConnected || app.catalog.sessionRevision != sessionRevision) {
      throw StateError('The connection or signed-in account changed.');
    }

    await app.resetListeningStatistics();
  }

  void beginReset() {
    if (isDisposed || saving || _resetting) {
      return;
    }

    update(() => _resetting = true);
  }

  void endReset() => update(() => _resetting = false);

  Future<void> reset(Future<void> Function() action, {required bool serverConnected}) async {
    if (isDisposed || saving) {
      return;
    }

    try {
      await action();
    } catch (error) {
      final message = serverConnected && error is ApiException && (error.statusCode == 404 || error.statusCode == 405)
          ? 'This server needs an update to reset listening statistics.'
          : 'Could not reset listening statistics. Check your connection and try again.';

      AppLogger.warning('$message $error');
    }
  }
}
