import 'package:phonolite_app/data/storage/preferences/log_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/infrastructure/platform/files/macos_directory_access.dart';

/// Reacquire grants before logs, databases or downloads open their saved paths.
class RestoreStorageAccess {
  final MacosDirectoryAccess access;
  final LogStorageSettingsStorage logs;
  final OfflineStorageSettingsStorage offline;

  const RestoreStorageAccess({
    this.access = const MacosDirectoryAccess(),
    this.logs = const LogStorageSettingsStorage(),
    this.offline = const OfflineStorageSettingsStorage(),
  });

  Future<List<String>> restore() async {
    if (!access.isSupported) {
      return const [];
    }

    final restored = await access.restore();
    final settings = await offline.read();
    final metadata = restored.resolve(settings.metadataDirectory);
    final downloads = restored.resolve(settings.downloadsDirectory);

    if (metadata != settings.metadataDirectory || downloads != settings.downloadsDirectory) {
      await offline.write(settings.copyWith(metadataDirectory: metadata, downloadsDirectory: downloads));
    }

    final logDirectory = await logs.read();
    final restoredLogs = restored.unavailable.contains(logDirectory) ? null : restored.resolve(logDirectory);

    if (restoredLogs != logDirectory) {
      await logs.write(restoredLogs);
    }

    return [
      if (restored.unavailable.isNotEmpty)
        'Some saved storage folders are unavailable. Reconnect the volume or choose the folder again in Settings.',
      if (logDirectory != null && restoredLogs == null) 'Logs were returned to the default folder.',
    ];
  }
}
