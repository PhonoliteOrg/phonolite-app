import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class CustomShuffleSettingsStorage {
  static const String _fileName = 'shuffle_settings.json';

  final SettingsFiles _files;

  const CustomShuffleSettingsStorage({SettingsFiles files = const SettingsFiles(cacheFirst: true)}) : _files = files;

  JsonSettingsFile get _file => JsonSettingsFile(name: _fileName, files: _files);

  Future<CustomShuffleSettings> read() async {
    if (kIsWeb) {
      return const CustomShuffleSettings();
    }

    try {
      final value = await _file.read();
      if (value == null) {
        return const CustomShuffleSettings();
      }

      return CustomShuffleSettings.fromJson(value);
    } catch (err) {
      AppLogger.warning('Failed to read shuffle settings: $err');

      return const CustomShuffleSettings();
    }
  }

  Future<void> write(CustomShuffleSettings settings) async {
    if (kIsWeb) {
      return;
    }

    try {
      await _file.write(settings.toJson());
    } catch (err) {
      AppLogger.warning('Failed to persist shuffle settings: $err');
    }
  }
}
