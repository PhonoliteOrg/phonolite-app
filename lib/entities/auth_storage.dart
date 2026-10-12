import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_log.dart';
import 'server_trust.dart';

@immutable
class AuthCredentials {
  const AuthCredentials({
    required this.baseUrl,
    required this.token,
    required this.username,
    this.serverId,
    this.userId,
    required this.trust,
  });

  final String baseUrl;
  final String token;
  final String username;
  final String? serverId;
  final String? userId;
  final ServerTrust trust;

  Map<String, dynamic> toJson() => {
    'profile': 'phonolite-opaque-v1',
    'baseUrl': baseUrl,
    'token': token,
    'username': username,
    if (serverId != null) 'serverId': serverId,
    if (userId != null) 'userId': userId,
    'trust': trust.toJson(),
  };

  static AuthCredentials? fromJson(Map<String, dynamic> json) {
    final baseUrl = json['baseUrl']?.toString() ?? '';
    final token = json['token']?.toString() ?? '';
    final username = json['username']?.toString() ?? '';
    final uri = Uri.tryParse(baseUrl);
    final trust = ServerTrust.fromJson(json['trust']);
    if (json['profile'] != 'phonolite-opaque-v1' ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        token.isEmpty ||
        username.trim().isEmpty ||
        trust == null) {
      return null;
    }
    return AuthCredentials(
      baseUrl: baseUrl,
      token: token,
      username: username,
      serverId: json['serverId']?.toString(),
      userId: json['userId']?.toString(),
      trust: trust,
    );
  }
}

class AuthStorage {
  const AuthStorage();

  static const _vault = FlutterSecureStorage();
  static const _vaultKey = 'phonolite.auth.session.v1';

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
      await _vault.write(
        key: _vaultKey,
        value: jsonEncode(credentials.toJson()),
      );
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
}
