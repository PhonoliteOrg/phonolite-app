import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:phonolite_app/data/models/auth/server_trust.dart';

/// Persists authenticated server pins under their normalized origin.
class ServerTrustStore {
  static const FlutterSecureStorage _vault = FlutterSecureStorage();

  static Future<ServerTrust?> read(String url) async {
    final raw = await _vault.read(key: _key(url));

    return raw == null ? null : ServerTrust.fromJson(jsonDecode(raw));
  }

  static Future<void> write(String url, ServerTrust trust) =>
      _vault.write(key: _key(url), value: jsonEncode(trust.toJson()));

  static String _key(String url) =>
      'phonolite.trust.v1.${base64Url.encode(utf8.encode(ServerTrust.origin(Uri.parse(url))))}';
}
