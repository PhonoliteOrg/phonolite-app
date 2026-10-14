import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../persistence/settings_files.dart';

@immutable
class LogStorageLocation {
  const LogStorageLocation({required this.directory, required this.isDefault});

  final String directory;
  final bool isDefault;
}

class LogStorageSettingsStorage {
  const LogStorageSettingsStorage({
    SettingsFiles files = const SettingsFiles(),
    bool Function()? usesManagedStoragePaths,
  }) : _files = files,
       _usesManagedStoragePaths = usesManagedStoragePaths;

  final SettingsFiles _files;
  final bool Function()? _usesManagedStoragePaths;

  bool get usesManagedStoragePaths =>
      _usesManagedStoragePaths?.call() ?? (!kIsWeb && Platform.isIOS);

  Future<String?> read() async {
    if (kIsWeb || usesManagedStoragePaths) return null;
    try {
      final file = await _files.resolve('log_storage.json');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      final path = decoded is Map ? decoded['directory'] : null;
      return path is String && path.trim().isNotEmpty
          ? Directory(path.trim()).absolute.path
          : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String? directory) async {
    if (kIsWeb) return;
    final file = await _files.resolve(
      'log_storage.json',
      createDirectory: true,
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'directory': usesManagedStoragePaths ? null : directory}),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
