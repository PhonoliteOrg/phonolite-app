import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/data/storage/auth/credential_vault.dart';

/// Persists authenticated server pins under their normalized origin.
class ServerTrustStore {
  static const FlutterSecureStorage _vault = CredentialVault.storage;
  static final Map<String, Future<void>> _mutations = {};

  static Future<ServerTrust?> read(String url) async {
    final raw = await _vault.read(key: keyForServer(url));

    return raw == null ? null : ServerTrust.fromJson(jsonDecode(raw));
  }

  static Future<void> write(String url, ServerTrust trust) =>
      _mutate(url, (key) => _vault.write(key: key, value: jsonEncode(trust.toJson())));

  /// Removes only this origin's identity after any already-started pin write.
  static Future<void> remove(String url) =>
      _mutate(url, (key) => _vault.delete(key: key, iOptions: CredentialVault.allIOSAccessibilities));

  static Future<void> _mutate(String url, Future<void> Function(String key) operation) async {
    final key = keyForServer(url);
    final pending = (_mutations[key] ?? Future<void>.value()).catchError((Object _) {}).then((_) => operation(key));
    _mutations[key] = pending;

    try {
      await pending;
    } finally {
      if (identical(_mutations[key], pending)) {
        _mutations.remove(key);
      }
    }
  }

  static String keyForServer(String url) =>
      'phonolite.trust.v1.${base64Url.encode(utf8.encode(ServerTrust.origin(Uri.parse(url))))}';
}
