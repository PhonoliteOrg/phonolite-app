import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/infrastructure/platform/files/desktop_directory_service.dart';

export 'package:phonolite_app/application/controllers/settings/listening_statistics_controller.dart';
export 'package:phonolite_app/application/controllers/settings/storage_path_controller.dart';

class SettingsController {
  static final SettingsController instance = SettingsController();

  Stream<LogStorageLocation> get storageLocationStream => AppLogger.instance.storageLocationStream;

  LogStorageLocation? get storageLocation => AppLogger.instance.storageLocation;

  Future<void> updateStorageDirectory(String? path) => AppLogger.instance.updateStorageDirectory(path);

  Future<bool> openStorageDirectory(String path) async {
    try {
      await const DesktopDirectoryService().openDirectory(path);

      return true;
    } catch (error) {
      AppLogger.warning('Could not open storage folder: $error');

      return false;
    }
  }

  Future<bool> resetLogsStorage() async {
    try {
      await updateStorageDirectory(null);

      return true;
    } catch (error) {
      AppLogger.warning('Could not reset logs storage: $error');

      return false;
    }
  }
}
