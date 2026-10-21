import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/auth/server_trust.dart';

@immutable
class AuthCredentials {
  final String baseUrl;
  final String token;
  final String username;
  final String? serverId;
  final String? userId;
  final ServerTrust trust;

  const AuthCredentials({
    required this.baseUrl,
    required this.token,
    required this.username,
    required this.trust,
    this.serverId,
    this.userId,
  });

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

  Map<String, dynamic> toJson() => {
    'profile': 'phonolite-opaque-v1',
    'baseUrl': baseUrl,
    'token': token,
    'username': username,
    if (serverId != null) 'serverId': serverId,
    if (userId != null) 'userId': userId,
    'trust': trust.toJson(),
  };
}
