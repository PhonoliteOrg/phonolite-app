import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../persistence/settings_files.dart';

import 'app_log.dart';

class PlaybackPreferencesStorage {
  const PlaybackPreferencesStorage({
    SettingsFiles files = const SettingsFiles(),
  }) : _files = files;

  static const String _fileName = 'playback_prefs.json';
  // Serialize read-modify-write operations across instances targeting one file.
  static final Map<String, Future<void>> _writes = {};

  static const String _volumeKey = 'volume';
  static const String _collectionListModeKey = 'collection_list_mode';

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

  Future<Map<String, dynamic>?> _readPreferences({File? source}) async {
    if (kIsWeb) {
      return null;
    }
    try {
      final file = source ?? await _resolveFile();
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
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
      final file = await _resolveFile(createDir: true);
      final path = file.absolute.path;
      final keyPath = Platform.isWindows ? path.toLowerCase() : path;
      final previous = _writes[keyPath] ?? Future<void>.value();
      final next = previous.then((_) async {
        try {
          final payload =
              await _readPreferences(source: file) ?? <String, dynamic>{};
          payload[key] = value;
          await file.writeAsString(jsonEncode(payload));
        } catch (err) {
          AppLogger.warning('Failed to persist playback prefs: $err');
        }
      });
      _writes[keyPath] = next;
      try {
        await next;
      } finally {
        if (identical(_writes[keyPath], next)) _writes.remove(keyPath);
      }
    } catch (err) {
      AppLogger.warning('Failed to persist playback prefs: $err');
    }
  }

  final SettingsFiles _files;

  Future<File> _resolveFile({bool createDir = false}) =>
      _files.resolve(_fileName, createDirectory: createDir);
}
