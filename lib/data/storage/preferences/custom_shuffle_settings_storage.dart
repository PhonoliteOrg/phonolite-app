import 'dart:convert';

import 'package:crypto/crypto.dart';
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
    return _read(_file);
  }

  Future<CustomShuffleSettings> readForAccount(String scope) async {
    final settings = await _read(_fileForAccount(scope));

    return CustomShuffleSettings(artistIds: settings.artistIds, genres: settings.genres);
  }

  /// Updates device-local filters while retaining unscoped server filters for
  /// explicit legacy import into an account preset.
  Future<void> writeLocal(CustomShuffleSettings settings) =>
      _update(_file, {'localArtistIds': settings.localArtistIds, 'localGenres': settings.localGenres});

  Future<void> writeForAccount(String scope, CustomShuffleSettings settings) =>
      _update(_fileForAccount(scope), {'artistIds': settings.artistIds, 'genres': settings.genres});

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

  JsonSettingsFile _fileForAccount(String scope) {
    if (scope.trim().isEmpty) {
      throw ArgumentError.value(scope, 'scope', 'An account storage scope is required.');
    }

    final digest = sha256.convert(utf8.encode(scope));

    return JsonSettingsFile(name: 'shuffle_settings_account_$digest.json', files: _files);
  }

  Future<CustomShuffleSettings> _read(JsonSettingsFile file) async {
    if (kIsWeb) {
      return const CustomShuffleSettings();
    }

    try {
      final value = await file.read();
      if (value == null) {
        return const CustomShuffleSettings();
      }

      return CustomShuffleSettings.fromJson(value);
    } catch (err) {
      AppLogger.warning('Failed to read shuffle settings: $err');

      return const CustomShuffleSettings();
    }
  }

  Future<void> _update(JsonSettingsFile file, Map<String, dynamic> values) async {
    if (kIsWeb) {
      return;
    }

    try {
      await file.update(
        (payload) => payload.addAll(values),
        onReadError: (error) => AppLogger.warning('Failed to read shuffle settings: $error'),
      );
    } catch (err) {
      AppLogger.warning('Failed to persist shuffle settings: $err');
    }
  }
}
