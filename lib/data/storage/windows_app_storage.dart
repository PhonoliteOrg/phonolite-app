import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows storage is rooted directly at Roaming AppData, without a vendor folder.
class WindowsAppStorage {
  /// Replaces the process environment when no environment is passed.
  ///
  /// The test runner sets an empty map so Windows test runs fall back to the
  /// mocked application-support directory instead of the user's real profile.
  @visibleForTesting
  static Map<String, String>? environmentOverride;

  static Directory? directory({Map<String, String>? environment}) {
    final appData = (environment ?? environmentOverride ?? Platform.environment)['APPDATA'];

    if (appData == null || appData.trim().isEmpty) {
      return null;
    }

    return Directory(_join(appData, 'Phonolite'));
  }

  static String _join(String parent, String child) =>
      '$parent${parent.endsWith('/') || parent.endsWith('\\') ? '' : Platform.pathSeparator}$child';
}
