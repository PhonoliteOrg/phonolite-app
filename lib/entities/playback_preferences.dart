import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

class PlaybackPreferencesStorage {
  const PlaybackPreferencesStorage();

  static const String _fileName = 'playback_prefs.json';

  Future<double?> readVolume() async {
    if (kIsWeb) {
      return null;
    }
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(decoded as Map);
      final rawVolume = map['volume'];
      if (rawVolume is! num) {
        return null;
      }
      final volume = rawVolume.toDouble();
      if (volume.isNaN || volume.isInfinite) {
        return null;
      }
      return volume.clamp(0.0, 1.0);
    } catch (err) {
      AppLogger.warning('Failed to read playback prefs: $err');
      return null;
    }
  }

  Future<void> writeVolume(double volume) async {
    if (kIsWeb) {
      return;
    }
    try {
      final file = await _resolveFile(createDir: true);
      final payload = <String, dynamic>{
        'volume': volume.clamp(0.0, 1.0),
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (err) {
      AppLogger.warning('Failed to persist playback prefs: $err');
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
