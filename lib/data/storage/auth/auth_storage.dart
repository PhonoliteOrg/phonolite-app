import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

class AuthStorage {
  static const FlutterSecureStorage _vault = FlutterSecureStorage();
  static const String _vaultKey = 'phonolite.auth.session.v1';
  final SettingsFiles _files;

  const AuthStorage({SettingsFiles files = const SettingsFiles()}) : _files = files;

  /// Before connecting, retain only security data owned by a remembered session.
  /// A saved server may be offline; cleanup never probes or authenticates it.
  /// Storage failures propagate instead of being mistaken for absent credentials.
  Future<void> removeOrphanedCredentials() async {
    if (kIsWeb) {
      return;
    }

    final stored = await _vault.readAll();
    AuthCredentials? credentials;
    final rawSession = stored[_vaultKey];

    if (rawSession != null) {
      try {
        final decoded = jsonDecode(rawSession);
        final saved = decoded is Map ? AuthCredentials.fromJson(Map<String, dynamic>.from(decoded)) : null;
        if (saved != null) {
          final uri = Uri.parse(saved.baseUrl);
          if (saved.token.trim().isNotEmpty &&
              uri.port >= 1 &&
              uri.port <= 65535 &&
              (uri.path.isEmpty || uri.path == '/' || uri.path == '/api')) {
            credentials = saved;
          }
        }
      } catch (_) {
        // An unsupported or malformed session cannot own persisted server keys.
      }
    }

    final retainedKeys = <String>{};
    if (credentials != null) {
      retainedKeys.add(_vaultKey);
      final trustKey = ServerTrustStore.keyForServer(credentials.baseUrl);
      final rawTrust = stored[trustKey];
      var matchingTrust = false;

      if (rawTrust != null) {
        try {
          final trust = ServerTrust.fromJson(jsonDecode(rawTrust));
          matchingTrust = trust?.spki == credentials.trust.spki && trust?.opaqueKey == credentials.trust.opaqueKey;
        } catch (_) {
          // Repair a redundant malformed pin from the saved session's identity.
        }
      }

      if (!matchingTrust) {
        await _vault.write(key: trustKey, value: jsonEncode(credentials.trust.toJson()));
      }
      retainedKeys.add(trustKey);
    }

    for (final key in stored.keys) {
      final appSecurityKey =
          key.startsWith('phonolite.auth.') ||
          key.startsWith('phonolite.trust.') ||
          key.startsWith('phonolite.session.');
      if (appSecurityKey && !retainedKeys.contains(key)) {
        await _vault.delete(key: key);
      }
    }

    final legacyCredentials = await _files.resolve('auth.json');
    if (await legacyCredentials.exists()) {
      await legacyCredentials.delete();
    }
  }

  Future<AuthCredentials?> read() async {
    if (kIsWeb) {
      return null;
    }

    try {
      final protected = await _vault.read(key: _vaultKey);

      if (protected != null) {
        final decoded = jsonDecode(protected);

        if (decoded is Map) {
          return AuthCredentials.fromJson(Map<String, dynamic>.from(decoded));
        }
      }

      return null;
    } catch (_) {
      AppLogger.warning('Failed to read stored auth');

      return null;
    }
  }

  Future<void> write(AuthCredentials credentials) async {
    if (kIsWeb) {
      return;
    }

    try {
      if (AuthCredentials.fromJson(credentials.toJson()) == null) {
        throw StateError('Invalid authenticated session');
      }

      await _vault.write(key: _vaultKey, value: jsonEncode(credentials.toJson()));
    } catch (_) {
      AppLogger.warning('Failed to persist auth');
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      return;
    }

    try {
      await _vault.delete(key: _vaultKey);
    } catch (_) {
      AppLogger.warning('Failed to clear auth');
    }
  }

  /// Forgetting one server must retain a remembered session for another origin.
  /// Propagate storage failures so the user can retry an incomplete removal.
  Future<void> clearForServer(String url) async {
    if (kIsWeb) {
      return;
    }

    final raw = await _vault.read(key: _vaultKey);
    if (raw == null) {
      return;
    }

    AuthCredentials? credentials;
    try {
      final decoded = jsonDecode(raw);
      credentials = decoded is Map ? AuthCredentials.fromJson(Map<String, dynamic>.from(decoded)) : null;
    } on FormatException {
      return;
    }

    if (credentials != null &&
        ServerTrust.origin(Uri.parse(credentials.baseUrl)) == ServerTrust.origin(Uri.parse(url))) {
      await _vault.delete(key: _vaultKey);
    }
  }
}
