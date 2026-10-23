import 'dart:io';

/// Windows storage is rooted directly at Roaming AppData, without a vendor folder.
class WindowsAppStorage {
  static Directory? directory({Map<String, String>? environment}) {
    final appData = (environment ?? Platform.environment)['APPDATA'];
    if (appData == null || appData.trim().isEmpty) return null;
    return Directory(_join(appData, 'Phonolite'));
  }

  static String _join(String parent, String child) =>
      '$parent${parent.endsWith('/') || parent.endsWith('\\') ? '' : Platform.pathSeparator}$child';
}
