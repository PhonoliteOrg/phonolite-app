import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/infrastructure/platform/files/macos_directory_access.dart';

/// Reacquire grants before logs, databases or downloads open their saved paths.
class RestoreStorageAccess {
  final MacosDirectoryAccess access;
  final PreferencesCoordinator preferences;

  RestoreStorageAccess({this.access = const MacosDirectoryAccess(), PreferencesCoordinator? preferences})
    : preferences = preferences ?? PreferencesCoordinator.shared;

  Future<List<String>> restore() async {
    if (!access.isSupported) {
      return const [];
    }

    final restored = await access.restore();
    final settings = await preferences.loadOfflineDirectories();
    final metadata = restored.resolve(settings.metadataDirectory);
    final downloads = restored.resolve(settings.downloadsDirectory);

    if (metadata != settings.metadataDirectory || downloads != settings.downloadsDirectory) {
      await preferences.saveOfflineDirectories(
        settings.copyWith(metadataDirectory: metadata, downloadsDirectory: downloads),
      );
    }

    final logDirectory = await preferences.loadLogDirectory();
    final restoredLogs = restored.unavailable.contains(logDirectory) ? null : restored.resolve(logDirectory);

    if (restoredLogs != logDirectory) {
      await preferences.saveLogDirectory(restoredLogs);
    }

    return [
      if (restored.unavailable.isNotEmpty)
        'Some saved storage folders are unavailable. Reconnect the volume or choose the folder again in Settings.',
      if (logDirectory != null && restoredLogs == null) 'Logs were returned to the default folder.',
    ];
  }
}
