import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/device_playback_snapshot.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/json_settings_file.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

/// Owns durable, serialized resume writes; device and account data never merge.
class PlaybackResumeStorage {
  static const schemaVersion = 1;

  final SettingsFiles files;
  Future<void> _pending = Future<void>.value();
  int _localGeneration = 0;
  final Map<String, int> _accountGenerations = {};

  PlaybackResumeStorage({this.files = const SettingsFiles()});

  JsonSettingsFile get _device => JsonSettingsFile(name: 'playback_resume.json', files: files, atomicWrites: true);

  Future<void> flush() => _pending;

  Future<DevicePlaybackSnapshot?> readLocal() async {
    await flush();

    final payload = await _read(_device);
    final value = payload?['local'];

    if (value is! Map) {
      return null;
    }

    try {
      return DevicePlaybackSnapshot.fromJson(Map<String, dynamic>.from(value));
    } on FormatException catch (error) {
      AppLogger.warning('Unable to restore device playback: $error');

      return null;
    }
  }

  Future<AccountPlaybackSnapshot?> readAccount(String scope) async {
    final file = _accountFile(scope);
    await flush();

    final payload = await _read(file);
    final value = payload?['snapshot'];

    if (value is! Map) {
      return null;
    }

    try {
      return AccountPlaybackSnapshot.fromJson(Map<String, dynamic>.from(value));
    } on FormatException catch (error) {
      AppLogger.warning('Unable to restore account playback: $error');

      return null;
    }
  }

  Future<String?> readActiveScope() async {
    await flush();

    final value = (await _read(_device))?['active_scope'];

    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> writeLocal(DevicePlaybackSnapshot snapshot, {bool activate = true}) {
    final generation = _localGeneration;
    final value = snapshot.toJson();

    return _enqueue(() async {
      if (generation != _localGeneration) {
        return;
      }

      await _update(_device, (payload) {
        final previous = payload['local'];

        if (previous is Map &&
            previous['schema_version'] is int &&
            previous['schema_version'] != DevicePlaybackSnapshot.schemaVersion) {
          throw const FormatException('Unsupported device playback snapshot version');
        }

        payload['local'] = value;

        if (activate) {
          payload['active_scope'] = 'local';
        }
      });
    });
  }

  Future<void> writeAccount(String scope, AccountPlaybackSnapshot snapshot, {bool activate = true}) {
    final file = _accountFile(scope);
    final generation = _accountGenerations[scope] ?? 0;
    final value = snapshot.toJson();

    return _enqueue(() async {
      if (generation != (_accountGenerations[scope] ?? 0)) {
        return;
      }

      await _update(file, (payload) => payload['snapshot'] = value);

      if (activate && generation == (_accountGenerations[scope] ?? 0)) {
        await _update(_device, (payload) => payload['active_scope'] = scope);
      }
    });
  }

  /// Clear advances the fence before waiting for I/O, retiring pending saves.
  Future<void> clearLocal() {
    _localGeneration++;

    return _enqueue(
      () => _update(_device, (payload) {
        payload.remove('local');

        if (payload['active_scope'] == 'local') {
          payload.remove('active_scope');
        }
      }),
    );
  }

  Future<void> clearAccount(String scope) {
    final file = _accountFile(scope);
    _accountGenerations[scope] = (_accountGenerations[scope] ?? 0) + 1;

    return _enqueue(() async {
      await _update(file, (payload) => payload.remove('snapshot'));
      await _update(_device, (payload) {
        if (payload['active_scope'] == scope) {
          payload.remove('active_scope');
        }
      });
    });
  }

  JsonSettingsFile _accountFile(String scope) {
    if (scope.trim().isEmpty || scope == 'local') {
      throw ArgumentError.value(scope, 'scope', 'A server/account identity is required');
    }

    final digest = sha256.convert(utf8.encode(scope));

    return JsonSettingsFile(name: 'playback_resume_account_$digest.json', files: files, atomicWrites: true);
  }

  Future<Map<String, dynamic>?> _read(JsonSettingsFile file) async {
    try {
      final payload = await file.read();

      if (payload == null) {
        return null;
      }

      _checkVersion(payload);

      return payload;
    } on FormatException catch (error) {
      AppLogger.warning('Unable to read playback checkpoint: $error');

      return null;
    } on FileSystemException catch (error) {
      AppLogger.warning('Unable to read playback checkpoint: $error');

      return null;
    }
  }

  Future<void> _update(JsonSettingsFile file, void Function(Map<String, dynamic>) change) => file.update((payload) {
    // Preserve snapshots written by a newer app instead of downgrading them.
    if (payload.isNotEmpty) {
      _checkVersion(payload);
    }

    payload['schema_version'] = schemaVersion;
    change(payload);
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    return next;
  }

  void _checkVersion(Map<String, dynamic> payload) {
    if (payload['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported playback storage version');
    }
  }
}
