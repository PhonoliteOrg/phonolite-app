part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

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
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to record pending file deletes: $err');
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
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read pending file deletes: $err');

        return const [];
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
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to clear pending file deletes: $err');
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

  Future<List<String>> readPendingFileDeletes() => _ownerCleanup.readPendingFileDeletes();

  Future<void> clearPendingFileDeletes(Iterable<String> paths) => _ownerCleanup.clearPendingFileDeletes(paths);

  Future<List<String>> _managedDeleteRootPaths() => _ownerCleanup._managedDeleteRootPaths();

  void _recordPendingFileDeletes(Database db, Iterable<String> paths, int createdAt, {List<String>? deleteRoots}) =>
      _ownerCleanup._recordPendingFileDeletes(db, paths, createdAt, deleteRoots: deleteRoots);
}
