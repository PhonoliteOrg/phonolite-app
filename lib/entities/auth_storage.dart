import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

@immutable
class AuthCredentials {
  const AuthCredentials({
    required this.baseUrl,
    required this.token,
    required this.username,
  });

  final String baseUrl;
  final String token;
  final String username;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'token': token,
        'username': username,
      };

  static AuthCredentials? fromJson(Map<String, dynamic> json) {
    final baseUrl = json['baseUrl']?.toString() ?? '';
    final token = json['token']?.toString() ?? '';
    final username = json['username']?.toString() ?? '';
    if (baseUrl.trim().isEmpty) {
      return null;
    }
    return AuthCredentials(
      baseUrl: baseUrl,
      token: token,
      username: username,
    );
  }
}

class AuthStorage {
  const AuthStorage();

  static const String _fileName = 'auth.json';

  Future<AuthCredentials?> read() async {
    if (kIsWeb) {
      return null;
    }
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AuthCredentials.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );
    } catch (err) {
      debugPrint('Failed to read stored auth: $err');
      return null;
    }
  }

  Future<void> write(AuthCredentials credentials) async {
    if (kIsWeb) {
      return;
    }
    try {
      final file = await _resolveFile(createDir: true);
      await file.writeAsString(jsonEncode(credentials.toJson()));
    } catch (err) {
      debugPrint('Failed to persist auth: $err');
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      return;
    }
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (err) {
      debugPrint('Failed to clear auth: $err');
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
