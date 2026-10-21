part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineDatabase {
  final OfflineLibraryStorage _host;

  _OfflineDatabase(this._host);

  Future<void> close() async {
    if (!_host.keepDatabaseOpen) {
      return;
    }

    final pending = OfflineLibraryStorage._openDatabases.values.toList();

    OfflineLibraryStorage._openDatabases.clear();

    for (final opening in pending) {
      (await opening).dispose();
    }
  }

  Future<File> _databaseFile({bool createDir = false}) async {
    final dir = await _host.metadataRoot(createDir: createDir);

    return File(_host._join(dir.path, OfflineLibraryStorage._databaseFileName));
  }

  Future<Database> _openDatabase() async {
    final file = await _databaseFile(createDir: true);

    if (!_host.keepDatabaseOpen) {
      return _initializeDatabase(file);
    }

    final key = file.absolute.path;
    final existing = OfflineLibraryStorage._openDatabases[key];
    if (existing != null) {
      return existing;
    }

    final opening = _initializeDatabase(file);

    OfflineLibraryStorage._openDatabases[key] = opening;

    try {
      return await opening;
    } catch (_) {
      OfflineLibraryStorage._openDatabases.remove(key);

      rethrow;
    }
  }

  void _releaseDatabase(Database? db) {
    if (!_host.keepDatabaseOpen) {
      db?.dispose();
    }
  }

  /// One lease protocol for offline stores. Each operation supplies its query
  /// and optional recovery policy; acquisition and release stay paired here.
  /// Recovery runs before release, matching the stores' original ordering.
  Future<T> _withDatabase<T>(
    FutureOr<T> Function(Database db) operation, {
    T Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    Database? db;

    try {
      db = await _host._openDatabase();

      return await operation(db);
    } catch (error, stackTrace) {
      if (onError != null) {
        return onError(error, stackTrace);
      }

      rethrow;
    } finally {
      _host._releaseDatabase(db);
    }
  }

  Future<Database> _initializeDatabase(File file) async {
    final db = sqlite3.open(file.path);

    try {
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('PRAGMA foreign_keys = ON');

      final hadMetadataTable = _host._metadataTableExists(db);
      final previousSchemaVersion = hadMetadataTable
          ? _host._readStoredSchemaVersion(db)
          : OfflineLibraryStorage._schemaVersion;
      final gcAlreadyRan = hadMetadataTable && _host._metadataFlag(db, 'orphan_gc_v7');

      if (!hadMetadataTable || previousSchemaVersion != OfflineLibraryStorage._schemaVersion) {
        _host._initSchema(db);
      }

      await _host._migrateJsonIndexIfNeeded(db);

      final repairLocation = file.parent.absolute.path;
      final previousLocation = db.select('SELECT value FROM metadata WHERE key = ?', ['artwork_repair_location_v1']);

      if (!hadMetadataTable ||
          previousSchemaVersion != OfflineLibraryStorage._schemaVersion ||
          !_host._metadataFlag(db, 'artwork_repair_v1') ||
          !_host._metadataFlag(db, 'playlist_artwork_repair_v1') ||
          previousLocation.isEmpty ||
          previousLocation.single['value'] != repairLocation) {
        await _host._repairCanonicalArtworkPaths(db);
        db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['artwork_repair_v1', '1']);
        db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['playlist_artwork_repair_v1', '1']);
        db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
          'artwork_repair_location_v1',
          repairLocation,
        ]);
      }

      if (hadMetadataTable && (previousSchemaVersion < OfflineLibraryStorage._schemaVersion || !gcAlreadyRan)) {
        await _host._runStartupGarbageCollection(db);
        db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['orphan_gc_v7', '1']);
      } else if (!hadMetadataTable) {
        db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['orphan_gc_v7', '1']);
      }

      return db;
    } catch (_) {
      db.dispose();

      rethrow;
    }
  }

  void _transaction(Database db, void Function() body) {
    db.execute('BEGIN IMMEDIATE');

    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');

      rethrow;
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineDatabaseFacade {
  _OfflineDatabase get _ownerDatabase;

  Future<void> close() => _ownerDatabase.close();

  Future<Database> _openDatabase() => _ownerDatabase._openDatabase();

  void _releaseDatabase(Database? db) => _ownerDatabase._releaseDatabase(db);

  Future<T> _withDatabase<T>(
    FutureOr<T> Function(Database db) operation, {
    T Function(Object error, StackTrace stackTrace)? onError,
  }) => _ownerDatabase._withDatabase(operation, onError: onError);

  void _transaction(Database db, void Function() body) => _ownerDatabase._transaction(db, body);
}
