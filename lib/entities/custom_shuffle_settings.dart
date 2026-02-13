import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

@immutable
class CustomShuffleSettings {
  const CustomShuffleSettings({
    this.artistIds = const [],
    this.genres = const [],
  });

  final List<String> artistIds;
  final List<String> genres;

  CustomShuffleSettings copyWith({
    List<String>? artistIds,
    List<String>? genres,
  }) {
    return CustomShuffleSettings(
      artistIds: artistIds ?? this.artistIds,
      genres: genres ?? this.genres,
    );
  }

  Map<String, dynamic> toJson() => {
        'artistIds': artistIds,
        'genres': genres,
      };

  static CustomShuffleSettings fromJson(Map<String, dynamic> json) {
    return CustomShuffleSettings(
      artistIds: _normalizeList(json['artistIds']),
      genres: _normalizeList(json['genres'], lowerCase: true),
    );
  }

  static List<String> _normalizeList(
    dynamic value, {
    bool lowerCase = false,
  }) {
    if (value is! List) {
      return const [];
    }
    final seen = <String>{};
    final result = <String>[];
    for (final item in value) {
      var text = item?.toString() ?? '';
      text = text.trim();
      if (text.isEmpty) {
        continue;
      }
      if (lowerCase) {
        text = text.toLowerCase();
      }
      if (seen.add(text)) {
        result.add(text);
      }
    }
    return result;
  }
}

class CustomShuffleSettingsStorage {
  const CustomShuffleSettingsStorage();

  static const String _fileName = 'shuffle_settings.json';

  Future<CustomShuffleSettings> read() async {
    if (kIsWeb) {
      return const CustomShuffleSettings();
    }
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return const CustomShuffleSettings();
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const CustomShuffleSettings();
      }
      return CustomShuffleSettings.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );
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
      final file = await _resolveFile(createDir: true);
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (err) {
      AppLogger.warning('Failed to persist shuffle settings: $err');
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
