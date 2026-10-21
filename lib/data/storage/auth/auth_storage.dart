import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class AuthStorage {
  static const FlutterSecureStorage _vault = FlutterSecureStorage();
  static const String _vaultKey = 'phonolite.auth.session.v1';

  const AuthStorage();

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
