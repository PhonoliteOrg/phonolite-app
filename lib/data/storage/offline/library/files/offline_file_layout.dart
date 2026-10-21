part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineFileLayout {
  final OfflineLibraryStorage _host;

  _OfflineFileLayout(this._host);

  Future<File> trackFile({required String serverBaseUrl, required String trackId, String extension = 'audio'}) async {
    final dir = await _trackDirectory(serverBaseUrl, createDir: true);
    final safeExtension = OfflineLibraryStorage._safePathToken(extension).replaceAll('.', '');

    return File(_join(dir.path, '${OfflineLibraryStorage._safePathToken(trackId)}.$safeExtension'));
  }

  Future<File?> findExistingTrackFile({
    required String serverBaseUrl,
    required String trackId,
    required Iterable<String> extensions,
  }) async {
    final dir = await _trackDirectory(serverBaseUrl);
    final seen = <String>{};

    for (final extension in extensions) {
      final trimmed = extension.trim().replaceAll('.', '');

      if (trimmed.isEmpty) {
        continue;
      }

      final safeExtension = OfflineLibraryStorage._safePathToken(trimmed).replaceAll('.', '');

      if (safeExtension.isEmpty || !seen.add(safeExtension)) {
        continue;
      }

      final file = File(_join(dir.path, '${OfflineLibraryStorage._safePathToken(trackId)}.$safeExtension'));

      if (await file.exists()) {
        return file;
      }
    }

    return null;
  }

  Future<File> partialTrackFile({required String serverBaseUrl, required String trackId}) async {
    final dir = await _trackDirectory(serverBaseUrl, createDir: true);

    return File(
      _join(dir.path, '${OfflineLibraryStorage._safePathToken(trackId)}.${OfflineLibraryStorage._partialExtension}'),
    );
  }

  Future<File> albumArtFile({required String albumId, required String extension}) async {
    final dir = await _artDirectory(OfflineLibraryStorage._albumArtDirName, createDir: true);
    final safeExtension = OfflineLibraryStorage._safePathToken(extension).replaceAll('.', '');

    return File(_join(dir.path, '${OfflineLibraryStorage._safePathToken(albumId)}.$safeExtension'));
  }

  Future<File> artistArtFile({required String artistId, required String kind, required String extension}) async {
    final dir = await _artDirectory(OfflineLibraryStorage._artistArtDirName, createDir: true);
    final safeExtension = OfflineLibraryStorage._safePathToken(extension).replaceAll('.', '');
    final safeName = '${OfflineLibraryStorage._safePathToken(artistId)}_${OfflineLibraryStorage._safePathToken(kind)}';

    return File(_join(dir.path, '$safeName.$safeExtension'));
  }

  Future<File> playlistArtFile({required String playlistId, required String extension}) async {
    final dir = await _artDirectory(OfflineLibraryStorage._playlistArtDirName, createDir: true);
    final safeExtension = OfflineLibraryStorage._safePathToken(extension).replaceAll('.', '');

    return File(_join(dir.path, '${OfflineLibraryStorage._safePathToken(playlistId)}.$safeExtension'));
  }

  Future<Directory> offlineRoot({bool createDir = false}) async {
    return _host.metadataRoot(createDir: createDir);
  }

  Future<Directory> metadataRoot({bool createDir = false}) async {
    final locations = await _host.resolveStorageLocations();
    final dir = Directory(locations.metadataDirectory);

    if (createDir) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  Future<Directory> downloadsRoot({bool createDir = false}) async {
    final locations = await _host.resolveStorageLocations();
    final dir = Directory(locations.downloadsDirectory);

    if (createDir) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  static String extensionFromContentType(String? contentType) {
    final value = contentType?.split(';').first.trim().toLowerCase() ?? '';

    switch (value) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';
      case 'audio/mp4':
      case 'audio/x-m4a':
        return 'm4a';
      case 'audio/flac':
      case 'audio/x-flac':
        return 'flac';
      case 'audio/ogg':
      case 'application/ogg':
        return 'ogg';
      case 'audio/opus':
        return 'opus';
      case 'audio/aac':
        return 'aac';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';
      default:
        return 'audio';
    }
  }

  static String extensionFromImageContentType(String? contentType) {
    final value = contentType?.split(';').first.trim().toLowerCase() ?? '';

    switch (value) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'img';
    }
  }

  static String? extensionFromContentDisposition(String? contentDisposition) {
    final value = contentDisposition?.trim();

    if (value == null || value.isEmpty) {
      return null;
    }

    final match = RegExp("filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?", caseSensitive: false).firstMatch(value);
    final filename = match?.group(1)?.trim();

    if (filename == null || filename.isEmpty || !filename.contains('.')) {
      return null;
    }

    final extension = filename.split('.').last.trim().toLowerCase();

    if (extension.isEmpty) {
      return null;
    }

    return OfflineLibraryStorage._safePathToken(Uri.decodeComponent(extension)).replaceAll('.', '');
  }

  Future<void> _deleteOfflineDownloadFiles(Directory downloadsDir) async {
    if (!await downloadsDir.exists()) {
      return;
    }

    await for (final entity in downloadsDir.list(recursive: false)) {
      if (entity is! Directory) {
        continue;
      }

      final name = entity.path.split(Platform.pathSeparator).last;

      if (name.startsWith('server_')) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Iterable<String> _artworkExtensionCandidates(String? path) sync* {
    final pathExtension = _host._extensionFromPath(path);

    if (pathExtension != null) {
      yield pathExtension;
    }

    yield 'jpg';
    yield 'jpeg';
    yield 'png';
    yield 'webp';
    yield 'gif';
    yield 'img';
  }

  Future<Directory> _trackDirectory(String serverBaseUrl, {bool createDir = false}) async {
    final root = await _host.downloadsRoot(createDir: createDir);
    final serverDir = Directory(_join(root.path, 'server_${OfflineLibraryStorage._serverKey(serverBaseUrl)}'));
    final tracksDir = Directory(_join(serverDir.path, OfflineLibraryStorage._tracksDirName));

    if (createDir) {
      await tracksDir.create(recursive: true);
    }

    return tracksDir;
  }

  Future<Directory> _artDirectory(String childDirectory, {bool createDir = false}) async {
    final root = await _host.metadataRoot(createDir: createDir);
    final dir = Directory(_join(_join(root.path, OfflineLibraryStorage._artDirName), childDirectory));

    if (createDir) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  static String _sourceKey(String serverBaseUrl, String trackId) {
    return '$serverBaseUrl\n$trackId';
  }

  static String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  static String _serverKey(String baseUrl) {
    final encoded = base64Url.encode(utf8.encode(baseUrl.trim()));

    return encoded.replaceAll('=', '');
  }

  static String _safePathToken(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return 'item';
    }

    final out = StringBuffer();

    for (final codeUnit in trimmed.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      final safe =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122) ||
          ch == '-' ||
          ch == '_' ||
          ch == '.';

      out.write(safe ? ch : '_');
    }

    final text = out.toString();

    return text.isEmpty ? 'item' : text;
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

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineFileLayoutFacade {
  _OfflineFileLayout get _ownerFiles;

  Future<File> trackFile({required String serverBaseUrl, required String trackId, String extension = 'audio'}) =>
      _ownerFiles.trackFile(serverBaseUrl: serverBaseUrl, trackId: trackId, extension: extension);

  Future<File?> findExistingTrackFile({
    required String serverBaseUrl,
    required String trackId,
    required Iterable<String> extensions,
  }) => _ownerFiles.findExistingTrackFile(serverBaseUrl: serverBaseUrl, trackId: trackId, extensions: extensions);

  Future<File> partialTrackFile({required String serverBaseUrl, required String trackId}) =>
      _ownerFiles.partialTrackFile(serverBaseUrl: serverBaseUrl, trackId: trackId);

  Future<File> albumArtFile({required String albumId, required String extension}) =>
      _ownerFiles.albumArtFile(albumId: albumId, extension: extension);

  Future<File> artistArtFile({required String artistId, required String kind, required String extension}) =>
      _ownerFiles.artistArtFile(artistId: artistId, kind: kind, extension: extension);

  Future<File> playlistArtFile({required String playlistId, required String extension}) =>
      _ownerFiles.playlistArtFile(playlistId: playlistId, extension: extension);

  Future<Directory> offlineRoot({bool createDir = false}) => _ownerFiles.offlineRoot(createDir: createDir);

  Future<Directory> metadataRoot({bool createDir = false}) => _ownerFiles.metadataRoot(createDir: createDir);

  Future<Directory> downloadsRoot({bool createDir = false}) => _ownerFiles.downloadsRoot(createDir: createDir);

  Future<void> _deleteOfflineDownloadFiles(Directory downloadsDir) =>
      _ownerFiles._deleteOfflineDownloadFiles(downloadsDir);

  Future<void> _deleteFileIfExists(File file) => _ownerFiles._deleteFileIfExists(file);

  Future<void> _deleteDirectoryIfExists(Directory directory) => _ownerFiles._deleteDirectoryIfExists(directory);

  Iterable<String> _artworkExtensionCandidates(String? path) => _ownerFiles._artworkExtensionCandidates(path);

  Future<Directory> _artDirectory(String childDirectory, {bool createDir = false}) =>
      _ownerFiles._artDirectory(childDirectory, createDir: createDir);

  String _join(String left, String right) => _ownerFiles._join(left, right);
}
