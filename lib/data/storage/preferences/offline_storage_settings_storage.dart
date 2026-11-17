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

  const OfflineStorageSettingsStorage({this._files = const SettingsFiles(), this._usesManagedStoragePaths});

  bool get usesManagedStoragePaths => _usesManagedStoragePaths?.call() ?? (!kIsWeb && Platform.isIOS);

  JsonSettingsFile get _file => JsonSettingsFile(name: _fileName, files: _files, atomicWrites: true);

  Future<OfflineStorageSettings> read() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }

    final OfflineStorageSettings settings;

    try {
      settings = await _readFromDisk();
    } on FormatException catch (err) {
      // Content that does not decode is permanently unreadable, so it reads as the default locations and the
      // next location update replaces the file. A file that cannot be read right now (a FileSystemException)
      // propagates instead: treating it as the defaults would open another library and let a later update
      // overwrite the configured paths.
      AppLogger.warning('Offline storage settings are corrupt; using the default locations: $err');

      return const OfflineStorageSettings();
    }

    if (!usesManagedStoragePaths) {
      return settings;
    }

    if (settings.metadataDirectory != null || settings.downloadsDirectory != null) {
      try {
        await write(const OfflineStorageSettings());
      } on Object catch (_) {
        // Managed platforms always use the default locations, so stale paths left in the file change nothing;
        // write() has logged the failure and the next read retries clearing them.
      }
    }

    return const OfflineStorageSettings();
  }

  Future<OfflineStorageSettings> readRaw() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }

    try {
      return await _readFromDisk();
    } on Object catch (err) {
      // Only used to find legacy paths to migrate; without them there is nothing to migrate.
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
