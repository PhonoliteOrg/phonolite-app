import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/repositories/preferences_coordinator.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

import '../support/offline_library_test_helpers.dart';

/// Offline storage settings tell content that is permanently corrupt apart from a file that cannot be read right
/// now, so a transient failure never opens the default folder or overwrites the configured paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phonolite_offline_settings_failure_');
  });

  tearDown(() => temp.delete(recursive: true));

  group('offline storage settings', () {
    late _FlakyDirectory settingsDirectory;
    late OfflineStorageSettingsStorage settings;

    setUp(() {
      settingsDirectory = _FlakyDirectory(Directory(offlineTestJoin(temp.path, 'app_support')));
      settings = OfflineStorageSettingsStorage(
        files: SettingsFiles(directoryProvider: settingsDirectory.call),
        usesManagedStoragePaths: () => false,
      );
    });

    test('a settings file that cannot be read right now is not read as the defaults', () async {
      await settings.write(OfflineStorageSettings(metadataDirectory: offlineTestJoin(temp.path, 'custom')));
      settingsDirectory.failNext = true;

      await expectLater(settings.read(), throwsA(isA<FileSystemException>()));
      expect((await settings.read()).metadataDirectory, offlineTestJoin(temp.path, 'custom'));
    });

    test('corrupt settings content reads as the default locations', () async {
      final file = await SettingsFiles(directoryProvider: settingsDirectory.call)
          .resolve('offline_storage.json', createDirectory: true);

      await file.writeAsString('{not json');
      expect(await settings.read(), const OfflineStorageSettings());

      await file.writeAsBytes(<int>[0xff, 0xfe, 0x7b]);
      expect(await settings.read(), const OfflineStorageSettings());
    });

    test('a failed settings read keeps the configured downloads folder when moving metadata', () async {
      final library = OfflineLibraryStorage(
        defaultDirectoryProvider: () async => Directory(offlineTestJoin(temp.path, 'default_root')),
        preferences: PreferencesCoordinator(offline: settings),
      );
      final downloads = offlineTestJoin(temp.path, 'custom_downloads');

      await library.updateStorageLocations(
        metadataDirectory: offlineTestJoin(temp.path, 'custom_metadata'),
        downloadsDirectory: downloads,
      );
      settingsDirectory.failNext = true;

      await expectLater(
        library.updateStorageLocations(metadataDirectory: offlineTestJoin(temp.path, 'moved_metadata')),
        throwsA(isA<FileSystemException>()),
      );
      expect((await library.resolveStorageLocations()).downloadsDirectory, downloads);
    });
  });
}

/// A settings folder whose next lookup fails, as an unavailable volume would.
class _FlakyDirectory {
  final Directory directory;
  bool failNext = false;

  _FlakyDirectory(this.directory);

  Future<Directory> call() async {
    if (failNext) {
      failNext = false;

      throw FileSystemException('Injected settings folder failure', directory.path);
    }

    return directory;
  }
}
