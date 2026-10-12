import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../persistence/settings_files.dart';

import 'app_log.dart';

@immutable
class OfflineStorageSettings {
  const OfflineStorageSettings({
    this.metadataDirectory,
    this.downloadsDirectory,
  });

  final String? metadataDirectory;
  final String? downloadsDirectory;

  OfflineStorageSettings copyWith({
    Object? metadataDirectory = _offlineStorageUnset,
    Object? downloadsDirectory = _offlineStorageUnset,
  }) {
    return OfflineStorageSettings(
      metadataDirectory: metadataDirectory == _offlineStorageUnset
          ? this.metadataDirectory
          : metadataDirectory as String?,
      downloadsDirectory: downloadsDirectory == _offlineStorageUnset
          ? this.downloadsDirectory
          : downloadsDirectory as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'metadata_directory': metadataDirectory,
    'downloads_directory': downloadsDirectory,
  };

  static OfflineStorageSettings fromJson(Map<String, dynamic> json) {
    return OfflineStorageSettings(
      metadataDirectory: _optionalPath(json['metadata_directory']),
      downloadsDirectory: _optionalPath(json['downloads_directory']),
    );
  }

  static String? _optionalPath(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return Directory(text).absolute.path;
  }
}

@immutable
class OfflineStorageLocations {
  const OfflineStorageLocations({
    required this.metadataDirectory,
    required this.downloadsDirectory,
    required this.metadataDirectoryIsDefault,
    required this.downloadsDirectoryIsDefault,
  });

  final String metadataDirectory;
  final String downloadsDirectory;
  final bool metadataDirectoryIsDefault;
  final bool downloadsDirectoryIsDefault;
}

class OfflineStorageSettingsStorage {
  const OfflineStorageSettingsStorage({
    bool Function()? usesManagedStoragePaths,
    SettingsFiles files = const SettingsFiles(),
  }) : _usesManagedStoragePaths = usesManagedStoragePaths,
       _files = files;

  static const String _fileName = 'offline_storage.json';
  final bool Function()? _usesManagedStoragePaths;

  bool get usesManagedStoragePaths =>
      _usesManagedStoragePaths?.call() ?? (!kIsWeb && Platform.isIOS);

  Future<OfflineStorageSettings> read() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }
    try {
      final settings = await _readFromDisk();
      if (usesManagedStoragePaths) {
        if (settings.metadataDirectory != null ||
            settings.downloadsDirectory != null) {
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
      final next = usesManagedStoragePaths
          ? const OfflineStorageSettings()
          : settings;
      final file = await _resolveFile(createDir: true);
      await file.writeAsString(jsonEncode(next.toJson()));
    } catch (err) {
      AppLogger.warning('Failed to persist offline storage settings: $err');
      rethrow;
    }
  }

  Future<OfflineStorageSettings> _readFromDisk() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const OfflineStorageSettings();
    }
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const OfflineStorageSettings();
    }
    return OfflineStorageSettings.fromJson(Map<String, dynamic>.from(decoded));
  }

  final SettingsFiles _files;

  Future<File> _resolveFile({bool createDir = false}) =>
      _files.resolve(_fileName, createDirectory: createDir);
}

const Object _offlineStorageUnset = Object();
