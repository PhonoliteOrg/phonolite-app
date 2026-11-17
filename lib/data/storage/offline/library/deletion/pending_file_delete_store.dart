part of '../offline_library.dart';

class _PendingFileDeleteStore {
  final OfflineLibraryStorage _host;

  _PendingFileDeleteStore(this._host);

  Future<void> recordPendingFileDeletes(Iterable<String?> paths) async {
    if (kIsWeb) {
      return;
    }

    final deleteRoots = await _managedDeleteRootPaths();
    final pendingPaths = paths
        .map((path) => OfflineLibraryStorage._managedPendingDeletePath(path, deleteRoots))
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (pendingPaths.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          _recordPendingFileDeletes(db, pendingPaths, DateTime.now().millisecondsSinceEpoch);
        });
      },
    );
  }

  Future<bool> isManagedDeletePath(String path) async {
    if (kIsWeb) {
      return false;
    }

    final deleteRoots = await _managedDeleteRootPaths();

    return OfflineLibraryStorage._managedPendingDeletePath(path, deleteRoots) != null;
  }

  /// Whether library data references [path] again. File names are
  /// deterministic, so a re-download or new artwork can reuse a path whose
  /// earlier delete failed; cleanup must then keep the file and drop the row.
  Future<bool> isPendingFileDeleteReferenced(String path) async {
    if (kIsWeb) {
      return false;
    }

    final normalized = OfflineLibraryStorage._pendingDeletePath(path);

    if (normalized == null) {
      return false;
    }

    // An unreadable library cannot prove the path is unused; keep the file.
    return await _host._withDatabase((db) => _pathIsReferenced(db, normalized), onError: (err, stackTrace) => true);
  }

  Future<List<String>> readPendingFileDeletes() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return db
            .select('SELECT path FROM pending_file_deletes ORDER BY created_at, path')
            .map((row) => OfflineLibraryStorage._readString(row, 'path'))
            .where((path) => path.trim().isNotEmpty)
            .toList(growable: false);
      },
    );
  }

  Future<void> clearPendingFileDeletes(Iterable<String> paths) async {
    if (kIsWeb) {
      return;
    }

    final pendingPaths = paths
        .map(OfflineLibraryStorage._pendingDeletePath)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    if (pendingPaths.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final path in pendingPaths) {
            db.execute('DELETE FROM pending_file_deletes WHERE path = ?', [path]);
          }
        });
      },
    );
  }

  Future<List<String>> _managedDeleteRootPaths() async {
    final roots = <String>[
      (await _host.downloadsRoot()).absolute.path,
      _host._join((await _host.metadataRoot()).absolute.path, OfflineLibraryStorage._artDirName),
    ];

    return roots.map(OfflineLibraryStorage._normalizedRootPath).toList(growable: false);
  }

  static String? _pendingDeletePath(String? path) {
    final text = path?.trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return File(text).absolute.path;
  }

  static String? _managedPendingDeletePath(String? path, List<String> deleteRoots) {
    final normalized = OfflineLibraryStorage._pendingDeletePath(path);
    if (normalized == null) {
      return null;
    }

    return OfflineLibraryStorage._pathIsUnderAnyRoot(normalized, deleteRoots) ? normalized : null;
  }

  static void _addPendingDeletePath(Set<String> target, String? path, List<String> deleteRoots) {
    final normalized = OfflineLibraryStorage._managedPendingDeletePath(path, deleteRoots);

    if (normalized != null) {
      target.add(normalized);
    }
  }

  static String _normalizedRootPath(String path) {
    final absolute = Directory(path).absolute.path;
    final separator = Platform.pathSeparator;
    final normalized = absolute.endsWith(separator) ? absolute : '$absolute$separator';

    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _pathIsUnderAnyRoot(String path, List<String> roots) {
    final separator = Platform.pathSeparator;
    final absolute = File(path).absolute.path;
    final normalizedPath = Platform.isWindows ? absolute.toLowerCase() : absolute;

    for (final root in roots) {
      final rootWithoutSeparator = root.endsWith(separator) ? root.substring(0, root.length - separator.length) : root;

      if (normalizedPath == rootWithoutSeparator || normalizedPath.startsWith(root)) {
        return true;
      }
    }

    return false;
  }

  bool _pathIsReferenced(Database db, String path) {
    final collation = Platform.isWindows ? ' COLLATE NOCASE' : '';

    return db
        .select(
          '''
      SELECT 1 FROM source_tracks
      WHERE file_path = ?1$collation OR partial_path = ?1$collation
      UNION ALL
      SELECT 1 FROM tracks t
      JOIN source_tracks s ON s.local_track_id = t.id
      WHERE t.album_art_path = ?1$collation
         OR t.artist_art_path = ?1$collation
         OR t.artist_banner_path = ?1$collation
      UNION ALL
      SELECT 1 FROM local_playlists
      WHERE image_path = ?1$collation
      LIMIT 1
    ''',
          [path],
        )
        .isNotEmpty;
  }

  /// Writes that reference a path cancel any delete still pending for it.
  void _forgetPendingFileDeletes(Database db, Iterable<String?> paths) {
    final collation = Platform.isWindows ? ' COLLATE NOCASE' : '';

    for (final path in paths) {
      final normalized = OfflineLibraryStorage._pendingDeletePath(path);

      if (normalized != null) {
        db.execute('DELETE FROM pending_file_deletes WHERE path = ?$collation', [normalized]);
      }
    }
  }

  void _recordPendingFileDeletes(Database db, Iterable<String> paths, int createdAt, {List<String>? deleteRoots}) {
    final roots = deleteRoots;

    for (final path in paths) {
      final normalized = roots == null
          ? OfflineLibraryStorage._pendingDeletePath(path)
          : OfflineLibraryStorage._managedPendingDeletePath(path, roots);
      if (normalized == null) {
        continue;
      }

      db.execute(
        '''
        INSERT INTO pending_file_deletes (path, created_at)
        VALUES (?, ?)
        ON CONFLICT(path) DO NOTHING
      ''',
        [normalized, createdAt],
      );
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PendingFileDeleteStoreFacade {
  _PendingFileDeleteStore get _ownerCleanup;

  Future<void> recordPendingFileDeletes(Iterable<String?> paths) => _ownerCleanup.recordPendingFileDeletes(paths);

  Future<bool> isManagedDeletePath(String path) => _ownerCleanup.isManagedDeletePath(path);

  Future<bool> isPendingFileDeleteReferenced(String path) => _ownerCleanup.isPendingFileDeleteReferenced(path);

  Future<List<String>> readPendingFileDeletes() => _ownerCleanup.readPendingFileDeletes();

  Future<void> clearPendingFileDeletes(Iterable<String> paths) => _ownerCleanup.clearPendingFileDeletes(paths);

  Future<List<String>> _managedDeleteRootPaths() => _ownerCleanup._managedDeleteRootPaths();

  void _recordPendingFileDeletes(Database db, Iterable<String> paths, int createdAt, {List<String>? deleteRoots}) =>
      _ownerCleanup._recordPendingFileDeletes(db, paths, createdAt, deleteRoots: deleteRoots);

  void _forgetPendingFileDeletes(Database db, Iterable<String?> paths) =>
      _ownerCleanup._forgetPendingFileDeletes(db, paths);
}
