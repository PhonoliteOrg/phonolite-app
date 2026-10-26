import 'dart:io';

import 'package:phonolite_app/data/models/preferences/desktop_settings.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class DesktopSettingsStorage {
  final SettingsFiles files;

  const DesktopSettingsStorage({this.files = const SettingsFiles()});

  JsonSettingsFile get _file => JsonSettingsFile(name: 'desktop_settings.json', files: files, atomicWrites: true);

  Future<DesktopSettings> read() async {
    try {
      return DesktopSettings.fromJson(await _file.read() ?? {});
    } on FormatException {
      return const DesktopSettings();
    } on FileSystemException {
      return const DesktopSettings();
    }
  }

  Future<void> write(DesktopSettings settings) => _file.write(settings.toJson());
}
