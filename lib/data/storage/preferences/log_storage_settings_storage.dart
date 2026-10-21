import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class LogStorageSettingsStorage {
  final SettingsFiles _files;
  final bool Function()? _usesManagedStoragePaths;

  const LogStorageSettingsStorage({
    SettingsFiles files = const SettingsFiles(),
    bool Function()? usesManagedStoragePaths,
  }) : _files = files,
       _usesManagedStoragePaths = usesManagedStoragePaths;

  bool get usesManagedStoragePaths => _usesManagedStoragePaths?.call() ?? (!kIsWeb && Platform.isIOS);

  JsonSettingsFile get _file => JsonSettingsFile(name: 'log_storage.json', files: _files, atomicWrites: true);

  Future<String?> read() async {
    if (kIsWeb || usesManagedStoragePaths) {
      return null;
    }

    try {
      final value = await _file.read();
      final path = value?['directory'];

      return path is String && path.trim().isNotEmpty ? Directory(path.trim()).absolute.path : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String? directory) async {
    if (kIsWeb) {
      return;
    }

    await _file.write({'directory': usesManagedStoragePaths ? null : directory});
  }
}
