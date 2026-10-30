import 'dart:io';

import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/preferences/download_settings.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

/// Independent of storage-path preferences, which use managed defaults on iOS.
class DownloadSettingsStorage {
  final SettingsFiles files;

  const DownloadSettingsStorage({this.files = const SettingsFiles()});

  JsonSettingsFile get _file => JsonSettingsFile(name: 'download_settings.json', files: files, atomicWrites: true);

  Future<DownloadSettings> read() async {
    try {
      final value = await _file.read();

      if (value != null) return DownloadSettings.fromJson(value);

      if (await (await files.resolve('download_settings.json')).exists()) return const DownloadSettings();

      final existing = await _hasExistingInstallation();
      final settings = DownloadSettings(quality: existing ? DownloadQuality.original : DownloadQuality.high);

      // Record the one-time migration before other startup services create markers.
      await write(settings);

      return settings;
    } on FormatException {
      return const DownloadSettings();
    }
  }

  Future<void> write(DownloadSettings settings) => _file.write(settings.toJson());

  Future<bool> _hasExistingInstallation() async {
    for (final name in [
      'auth.json',
      'playback_prefs.json',
      'display_settings.json',
      'desktop_settings.json',
      'offline_storage.json',
      'shuffle_settings.json',
    ]) {
      if (await (await files.resolve(name)).exists()) return true;
    }

    final settingsFile = await files.resolve('download_settings.json');

    return Directory('${settingsFile.parent.path}${Platform.pathSeparator}offline').exists();
  }
}
