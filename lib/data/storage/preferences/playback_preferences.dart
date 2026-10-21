import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class PlaybackPreferencesStorage {
  static const String _fileName = 'playback_prefs.json';
  static const String _volumeKey = 'volume';
  static const String _collectionListModeKey = 'collection_list_mode';

  final SettingsFiles _files;

  const PlaybackPreferencesStorage({SettingsFiles files = const SettingsFiles()}) : _files = files;

  JsonSettingsFile get _file => JsonSettingsFile(name: _fileName, files: _files);

  Future<double?> readVolume() async {
    final map = await _readPreferences();
    if (map == null) {
      return null;
    }

    final rawVolume = map[_volumeKey];

    if (rawVolume is! num) {
      return null;
    }

    final volume = rawVolume.toDouble();

    if (volume.isNaN || volume.isInfinite) {
      return null;
    }

    return volume.clamp(0.0, 1.0);
  }

  Future<void> writeVolume(double volume) async {
    await _writePreference(_volumeKey, volume.clamp(0.0, 1.0));
  }

  Future<bool?> readCollectionListMode() async {
    final map = await _readPreferences();
    if (map == null) {
      return null;
    }

    final rawValue = map[_collectionListModeKey];

    if (rawValue is! bool) {
      return null;
    }

    return rawValue;
  }

  Future<void> writeCollectionListMode(bool value) async {
    await _writePreference(_collectionListModeKey, value);
  }

  Future<Map<String, dynamic>?> _readPreferences() async {
    if (kIsWeb) {
      return null;
    }

    try {
      return await _file.read();
    } catch (err) {
      AppLogger.warning('Failed to read playback prefs: $err');

      return null;
    }
  }

  Future<void> _writePreference(String key, Object value) async {
    if (kIsWeb) {
      return;
    }

    try {
      await _file.update(
        (payload) => payload[key] = value,
        onReadError: (error) => AppLogger.warning('Failed to read playback prefs: $error'),
      );
    } catch (err) {
      AppLogger.warning('Failed to persist playback prefs: $err');
    }
  }
}
