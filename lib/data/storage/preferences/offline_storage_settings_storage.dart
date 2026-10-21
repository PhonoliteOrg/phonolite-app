import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/preferences/offline_storage_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

export 'package:phonolite_app/data/models/preferences/offline_storage_settings.dart';

class OfflineStorageSettingsStorage {
  static const String _fileName = 'offline_storage.json';

  final bool Function()? _usesManagedStoragePaths;
  final SettingsFiles _files;

  const OfflineStorageSettingsStorage({
    SettingsFiles files = const SettingsFiles(),
    bool Function()? usesManagedStoragePaths,
  }) : _usesManagedStoragePaths = usesManagedStoragePaths,
       _files = files;

  bool get usesManagedStoragePaths => _usesManagedStoragePaths?.call() ?? (!kIsWeb && Platform.isIOS);

  JsonSettingsFile get _file => JsonSettingsFile(name: _fileName, files: _files);

  Future<OfflineStorageSettings> read() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }

    try {
      final settings = await _readFromDisk();

      if (usesManagedStoragePaths) {
        if (settings.metadataDirectory != null || settings.downloadsDirectory != null) {
          await write(const OfflineStorageSettings());
        }

        return const OfflineStorageSettings();
      }

      return settings;
    } catch (err) {
      AppLogger.warning('Failed to read offline storage settings: $err');

      return const OfflineStorageSettings();
    }
  }

  Future<OfflineStorageSettings> readRaw() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }

    try {
      return await _readFromDisk();
    } catch (err) {
      AppLogger.warning('Failed to read raw offline storage settings: $err');

      return const OfflineStorageSettings();
    }
  }

  Future<void> write(OfflineStorageSettings settings) async {
    if (kIsWeb) {
      return;
    }

    try {
      final next = usesManagedStoragePaths ? const OfflineStorageSettings() : settings;

      await _file.write(next.toJson());
    } catch (err) {
      AppLogger.warning('Failed to persist offline storage settings: $err');

      rethrow;
    }
  }

  Future<OfflineStorageSettings> _readFromDisk() async {
    final value = await _file.read();
    if (value == null) {
      return const OfflineStorageSettings();
    }

    return OfflineStorageSettings.fromJson(value);
  }
}
