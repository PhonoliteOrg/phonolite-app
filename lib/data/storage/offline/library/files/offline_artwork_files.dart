part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineArtworkFiles {
  final OfflineLibraryStorage _host;

  _OfflineArtworkFiles(this._host);

  Future<void> _repairCanonicalArtworkPaths(Database db) async {
    final rows = db.select('''
      SELECT
        id,
        album_id,
        album_art_path,
        artist_id,
        artist_art_path,
        artist_banner_path
      FROM tracks
      WHERE album_id IS NOT NULL
         OR artist_id IS NOT NULL
         OR album_art_path IS NOT NULL
         OR artist_art_path IS NOT NULL
         OR artist_banner_path IS NOT NULL
    ''');
    final playlistRows = db.select('SELECT id, image_path FROM local_playlists WHERE image_path IS NOT NULL');

    if (rows.isEmpty && playlistRows.isEmpty) {
      return;
    }

    final albumDir = await _host._artDirectory(OfflineLibraryStorage._albumArtDirName);
    final artistDir = await _host._artDirectory(OfflineLibraryStorage._artistArtDirName);
    final playlistDir = await _host._artDirectory(OfflineLibraryStorage._playlistArtDirName);

    _host._transaction(db, () {
      for (final row in rows) {
        final localTrackId = OfflineLibraryStorage._readString(row, 'id');
        final albumPath = OfflineLibraryStorage._readNullableString(row, 'album_art_path');
        final artistPath = OfflineLibraryStorage._readNullableString(row, 'artist_art_path');
        final bannerPath = OfflineLibraryStorage._readNullableString(row, 'artist_banner_path');
        final repairedAlbumPath = _repairCanonicalArtworkPathSync(
          directory: albumDir,
          id: OfflineLibraryStorage._readNullableString(row, 'album_id'),
          savedPath: albumPath,
        );
        final repairedArtistPath = _repairCanonicalArtworkPathSync(
          directory: artistDir,
          id: OfflineLibraryStorage._readNullableString(row, 'artist_id'),
          kind: 'logo',
          savedPath: artistPath,
        );
        final repairedBannerPath = _repairCanonicalArtworkPathSync(
          directory: artistDir,
          id: OfflineLibraryStorage._readNullableString(row, 'artist_id'),
          kind: 'banner',
          savedPath: bannerPath,
        );

        if (repairedAlbumPath == albumPath && repairedArtistPath == artistPath && repairedBannerPath == bannerPath) {
          continue;
        }

        db.execute(
          '''
          UPDATE tracks
          SET album_art_path = ?,
              artist_art_path = ?,
              artist_banner_path = ?
          WHERE id = ?
        ''',
          [repairedAlbumPath, repairedArtistPath, repairedBannerPath, localTrackId],
        );
      }

      for (final row in playlistRows) {
        final playlistId = OfflineLibraryStorage._readString(row, 'id');
        final savedPath = OfflineLibraryStorage._readNullableString(row, 'image_path');
        final repairedPath = _repairCanonicalArtworkPathSync(
          directory: playlistDir,
          id: playlistId,
          savedPath: savedPath,
        );

        if (repairedPath != savedPath) {
          db.execute('UPDATE local_playlists SET image_path = ? WHERE id = ?', [repairedPath, playlistId]);
        }
      }
    });
  }

  String? _repairCanonicalArtworkPathSync({
    required Directory directory,
    required String? id,
    required String? savedPath,
    String? kind,
  }) {
    if (_fileExistsSync(savedPath)) {
      return savedPath;
    }

    final trimmedId = id?.trim();

    if (trimmedId == null || trimmedId.isEmpty) {
      return savedPath;
    }

    final existing = _findExistingArtworkFileSync(
      directory: directory,
      id: trimmedId,
      kind: kind,
      extensions: _host._artworkExtensionCandidates(savedPath),
    );

    return existing?.path ?? savedPath;
  }

  File? _findExistingArtworkFileSync({
    required Directory directory,
    required String id,
    required String? kind,
    required Iterable<String> extensions,
  }) {
    final safeId = OfflineLibraryStorage._safePathToken(id);
    final safeName = kind == null ? safeId : '${safeId}_${OfflineLibraryStorage._safePathToken(kind)}';
    final seen = <String>{};

    for (final extension in extensions) {
      final safeExtension = OfflineLibraryStorage._safePathToken(
        extension.trim().replaceAll('.', ''),
      ).replaceAll('.', '');

      if (safeExtension.isEmpty || !seen.add(safeExtension)) {
        continue;
      }

      final file = File(_host._join(directory.path, '$safeName.$safeExtension'));

      if (file.existsSync()) {
        return file;
      }
    }

    return null;
  }

  bool _fileExistsSync(String? path) {
    final trimmed = path?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return false;
    }

    return File(trimmed).existsSync();
  }

  String? _extensionFromPath(String? path) {
    final trimmed = path?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final name = trimmed.split(RegExp(r'[/\\]')).last;
    final index = name.lastIndexOf('.');

    if (index < 0 || index == name.length - 1) {
      return null;
    }

    final extension = name.substring(index + 1).trim();

    return extension.isEmpty ? null : extension;
  }

  Future<List<String>> _unusedArtworkFiles(Database db, List<String> deleteRoots) async {
    final root = await _host.metadataRoot();
    final artRoot = Directory(_host._join(root.path, OfflineLibraryStorage._artDirName));

    if (!await artRoot.exists()) {
      return const <String>[];
    }

    final paths = <String>{};

    await for (final entity in artRoot.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }

      final path = OfflineLibraryStorage._managedPendingDeletePath(entity.path, deleteRoots);
      if (path == null) {
        continue;
      }

      if (!_artworkPathHasSourceBackedReference(db, path)) {
        paths.add(path);
      }
    }

    return paths.toList(growable: false);
  }

  bool _artworkPathHasSourceBackedReference(Database db, String path) {
    final trackBacked = db
        .select(
          '''
          SELECT 1
          FROM tracks t
          JOIN source_tracks s ON s.local_track_id = t.id
          WHERE t.album_art_path = ?
             OR t.artist_art_path = ?
             OR t.artist_banner_path = ?
          LIMIT 1
        ''',
          [path, path, path],
        )
        .isNotEmpty;

    if (trackBacked) {
      return true;
    }

    return db
        .select(
          '''
          SELECT 1
          FROM local_playlists
          WHERE image_path = ?
          LIMIT 1
        ''',
          [path],
        )
        .isNotEmpty;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineArtworkFilesFacade {
  _OfflineArtworkFiles get _ownerArtwork;

  Future<void> _repairCanonicalArtworkPaths(Database db) => _ownerArtwork._repairCanonicalArtworkPaths(db);

  String? _extensionFromPath(String? path) => _ownerArtwork._extensionFromPath(path);

  Future<List<String>> _unusedArtworkFiles(Database db, List<String> deleteRoots) =>
      _ownerArtwork._unusedArtworkFiles(db, deleteRoots);
}
