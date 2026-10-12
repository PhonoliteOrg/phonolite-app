import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../persistence/settings_files.dart';

import 'app_log.dart';

@immutable
class CustomShuffleSettings {
  const CustomShuffleSettings({
    this.artistIds = const [],
    this.genres = const [],
    this.localArtistIds = const [],
    this.localGenres = const [],
  });

  final List<String> artistIds;
  final List<String> genres;
  final List<String> localArtistIds;
  final List<String> localGenres;

  CustomShuffleSettings copyWith({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) {
    return CustomShuffleSettings(
      artistIds: artistIds ?? this.artistIds,
      genres: genres ?? this.genres,
      localArtistIds: localArtistIds ?? this.localArtistIds,
      localGenres: localGenres ?? this.localGenres,
    );
  }

  Map<String, dynamic> toJson() => {
    'artistIds': artistIds,
    'genres': genres,
    'localArtistIds': localArtistIds,
    'localGenres': localGenres,
  };

  static CustomShuffleSettings fromJson(Map<String, dynamic> json) {
    return CustomShuffleSettings(
      artistIds: _normalizeList(json['artistIds']),
      genres: _normalizeList(json['genres'], lowerCase: true),
      localArtistIds: _normalizeList(json['localArtistIds']),
      localGenres: _normalizeList(json['localGenres'], lowerCase: true),
    );
  }

  static List<String> _normalizeList(dynamic value, {bool lowerCase = false}) {
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
  const CustomShuffleSettingsStorage({
    SettingsFiles files = const SettingsFiles(cacheFirst: true),
  }) : _files = files;

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
      return CustomShuffleSettings.fromJson(Map<String, dynamic>.from(decoded));
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

  final SettingsFiles _files;

  Future<File> _resolveFile({bool createDir = false}) =>
      _files.resolve(_fileName, createDirectory: createDir);
}
