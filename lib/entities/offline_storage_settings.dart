import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  const OfflineStorageSettingsStorage();

  static const String _fileName = 'offline_storage.json';

  Future<OfflineStorageSettings> read() async {
    if (kIsWeb) {
      return const OfflineStorageSettings();
    }
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return const OfflineStorageSettings();
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const OfflineStorageSettings();
      }
      return OfflineStorageSettings.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (err) {
      AppLogger.warning('Failed to read offline storage settings: $err');
      return const OfflineStorageSettings();
    }
  }

  Future<void> write(OfflineStorageSettings settings) async {
    if (kIsWeb) {
      return;
    }
    try {
      final file = await _resolveFile(createDir: true);
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (err) {
      AppLogger.warning('Failed to persist offline storage settings: $err');
      rethrow;
    }
  }

  Future<File> _resolveFile({bool createDir = false}) async {
    final dir = await _resolveDirectory();
    if (createDir) {
      await dir.create(recursive: true);
    }
    return File(_join(dir.path, _fileName));
  }

  Future<Directory> _resolveDirectory() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        return Directory(_join(appData, 'Phonolite'));
      }
    }
    final supportDir = await getApplicationSupportDirectory();
    return Directory(_join(supportDir.path, 'Phonolite'));
  }

  String _join(String left, String right) {
    if (left.isEmpty) {
      return right;
    }
    final separator = Platform.pathSeparator;
    if (left.endsWith(separator)) {
      return '$left$right';
    }
    return '$left$separator$right';
  }
}

const Object _offlineStorageUnset = Object();
