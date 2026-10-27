import 'dart:io';

import 'package:phonolite_app/data/models/preferences/display_settings.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class DisplaySettingsStorage {
  final SettingsFiles files;

  const DisplaySettingsStorage({this.files = const SettingsFiles()});

  JsonSettingsFile get _file => JsonSettingsFile(name: 'display_settings.json', files: files, atomicWrites: true);

  Future<DisplaySettings> read() async {
    try {
      return DisplaySettings.fromJson(await _file.read() ?? {});
    } on FormatException {
      return const DisplaySettings();
    } on FileSystemException {
      return const DisplaySettings();
    }
  }

  Future<void> write(DisplaySettings settings) => _file.write(settings.toJson());
}
