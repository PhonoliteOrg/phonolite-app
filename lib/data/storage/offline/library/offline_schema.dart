part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineSchema {
  final OfflineLibraryStorage _host;

  _OfflineSchema(this._host);

  Future<File> _indexFile({bool createDir = false}) async {
    final dir = await _host.offlineRoot(createDir: createDir);

    return File(_host._join(dir.path, OfflineLibraryStorage._indexFileName));
  }

  bool _metadataTableExists(Database db) {
    try {
      return db.select('''
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table'
              AND name = 'metadata'
            LIMIT 1
          ''').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  int _readStoredSchemaVersion(Database db) {
    try {
      final rows = db.select('SELECT value FROM metadata WHERE key = ?', ['schema_version']);

      if (rows.isEmpty) {
        return 0;
      }

      return int.tryParse(OfflineLibraryStorage._readString(rows.first, 'value')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _metadataFlag(Database db, String key) {
    try {
      final rows = db.select('SELECT value FROM metadata WHERE key = ?', [key]);

      if (rows.isEmpty) {
        return false;
      }

      return OfflineLibraryStorage._readString(rows.first, 'value') == '1';
    } catch (_) {
      return false;
    }
  }

  void _initSchema(Database db) {
    db.execute('PRAGMA foreign_keys = ON');

    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS client_identity (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
        id TEXT PRIMARY KEY,
        match_key TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        artist_id TEXT,
        album TEXT NOT NULL,
        album_id TEXT,
        album_art_path TEXT,
        artist_art_path TEXT,
        artist_banner_path TEXT,
        genres_json TEXT NOT NULL DEFAULT '[]',
        duration_ms INTEGER NOT NULL,
        track_no INTEGER,
        disc_no INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_match_key ON tracks(match_key)');
    _ensureColumn(db, 'tracks', 'album_art_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'artist_art_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'artist_banner_path', 'TEXT');
    _ensureColumn(db, 'tracks', 'genres_json', "TEXT NOT NULL DEFAULT '[]'");

    db.execute('''
      CREATE TABLE IF NOT EXISTS source_tracks (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        batch_id TEXT,
        download_url TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        file_path TEXT,
        partial_path TEXT,
        bytes_downloaded INTEGER NOT NULL DEFAULT 0,
        bytes_total INTEGER,
        etag TEXT,
        expected_sha256 TEXT,
        content_type TEXT,
        error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (server_base_url, server_track_id),
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    _ensureColumn(db, 'source_tracks', 'batch_id', 'TEXT');
    _ensureColumn(db, 'source_tracks', 'download_url', 'TEXT');
    _ensureColumn(db, 'source_tracks', 'expected_sha256', 'TEXT');
    _ensureColumn(db, 'source_tracks', 'retry_count', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn(db, 'source_tracks', 'priority', 'INTEGER NOT NULL DEFAULT 0');
    db.execute('CREATE INDEX IF NOT EXISTS idx_source_tracks_local ON source_tracks(local_track_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_source_tracks_batch ON source_tracks(batch_id)');

    db.execute('''
      CREATE TABLE IF NOT EXISTS offline_metadata_fragments (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        track_json TEXT NOT NULL,
        album_json TEXT NOT NULL,
        artist_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, server_track_id),
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_offline_metadata_local ON offline_metadata_fragments(local_track_id)');

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_batches (
        batch_id TEXT PRIMARY KEY,
        server_base_url TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        completed_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        label TEXT
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_items (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        batch_id TEXT,
        local_track_id TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        file_path TEXT,
        partial_path TEXT,
        bytes_downloaded INTEGER NOT NULL DEFAULT 0,
        bytes_total INTEGER,
        etag TEXT,
        expected_sha256 TEXT,
        content_type TEXT,
        error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (server_base_url, server_track_id)
      )
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_download_items_batch ON download_items(batch_id)');

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_jobs (
        job_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        server_base_url TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        discovered_count INTEGER NOT NULL DEFAULT 0,
        completed_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        materialized_count INTEGER NOT NULL DEFAULT 0,
        source_cursor INTEGER NOT NULL DEFAULT 0,
        label TEXT,
        source_id TEXT,
        error TEXT
      )
    ''');
    _ensureColumn(db, 'download_jobs', 'source_id', 'TEXT');
    db.execute('CREATE INDEX IF NOT EXISTS idx_download_jobs_server ON download_jobs(server_base_url, status)');

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_job_items (
        job_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        server_track_id TEXT NOT NULL,
        status TEXT NOT NULL,
        materialized INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        track_json TEXT,
        metadata_json TEXT,
        error TEXT,
        PRIMARY KEY (job_id, server_track_id),
        FOREIGN KEY (job_id) REFERENCES download_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    _ensureColumn(db, 'download_job_items', 'metadata_json', 'TEXT');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_job_items_next ON download_job_items(job_id, materialized, position)',
    );

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_job_sources (
        job_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        source_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        label TEXT,
        error TEXT,
        PRIMARY KEY (job_id, source_id),
        FOREIGN KEY (job_id) REFERENCES download_jobs(job_id) ON DELETE CASCADE
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_job_sources_next ON download_job_sources(job_id, status, position)',
    );

    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata_snapshots (
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        snapshot_json TEXT NOT NULL,
        server_revision INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, kind, item_id)
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS file_artifacts (
        server_base_url TEXT NOT NULL,
        server_track_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        partial_path TEXT,
        byte_length INTEGER,
        etag TEXT,
        sha256 TEXT,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, server_track_id)
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS artwork_artifacts (
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        variant TEXT NOT NULL,
        file_path TEXT NOT NULL,
        content_type TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, kind, item_id, variant)
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        server_base_url TEXT NOT NULL,
        stream TEXT NOT NULL,
        cursor TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (server_base_url, stream)
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS repair_queue (
        id TEXT PRIMARY KEY,
        server_base_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS pending_file_deletes (
        path TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS local_likes (
        local_track_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS local_like_states (
        local_track_id TEXT PRIMARY KEY,
        liked INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');

    db.execute('''
      INSERT OR IGNORE INTO local_like_states (
        local_track_id,
        liked,
        updated_at
      )
      SELECT local_track_id, 1, created_at FROM local_likes
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS local_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        image_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    _ensureColumn(db, 'local_playlists', 'description', 'TEXT');
    _ensureColumn(db, 'local_playlists', 'image_path', 'TEXT');

    // A position identifies an entry so downloaded copies can retain repetitions.
    db.execute('''
      CREATE TABLE IF NOT EXISTS local_playlist_tracks (
        playlist_id TEXT NOT NULL,
        local_track_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, position),
        FOREIGN KEY (playlist_id) REFERENCES local_playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    final playlistColumns = db.select('PRAGMA table_info(local_playlist_tracks)');

    if (playlistColumns.any((row) => row['name'] == 'local_track_id' && row['pk'] != 0)) {
      _host._transaction(db, () {
        db.execute('''CREATE TABLE local_playlist_tracks_v11 (
          playlist_id TEXT NOT NULL,
          local_track_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (playlist_id, position),
          FOREIGN KEY (playlist_id) REFERENCES local_playlists(id) ON DELETE CASCADE,
          FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
        )''');
        db.execute('''INSERT INTO local_playlist_tracks_v11
          SELECT playlist_id, local_track_id,
            ROW_NUMBER() OVER (PARTITION BY playlist_id ORDER BY position, rowid) - 1
          FROM local_playlist_tracks''');
        db.execute('DROP TABLE local_playlist_tracks');
        db.execute('ALTER TABLE local_playlist_tracks_v11 RENAME TO local_playlist_tracks');
      });
    }

    db.execute('''CREATE TABLE IF NOT EXISTS pending_playlist_tracks (
      playlist_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      server_base_url TEXT NOT NULL,
      server_track_id TEXT NOT NULL,
      PRIMARY KEY (playlist_id, position),
      FOREIGN KEY (playlist_id) REFERENCES local_playlists(id) ON DELETE CASCADE
    )''');
    db.execute('''CREATE INDEX IF NOT EXISTS idx_pending_playlist_source
      ON pending_playlist_tracks(server_base_url, server_track_id)''');

    db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', [
      'schema_version',
      OfflineLibraryStorage._schemaVersion.toString(),
    ]);
  }

  Future<void> _migrateJsonIndexIfNeeded(Database db) async {
    final migrated = db.select('SELECT value FROM metadata WHERE key = ?', ['json_migrated']);

    if (migrated.isNotEmpty) {
      return;
    }

    final file = await _indexFile();

    if (!await file.exists()) {
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['json_migrated', '1']);

      return;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      final items = decoded is Map ? decoded['downloads'] : decoded;

      if (items is List) {
        _host._transaction(db, () {
          for (final item in items.whereType<Map>()) {
            final download = OfflineTrackDownload.fromJson(Map<String, dynamic>.from(item));

            if (download != null) {
              _host._upsertDownload(db, download);
            }
          }

          db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['json_migrated', '1']);
        });
      }
    } catch (err) {
      AppLogger.warning('Failed to migrate offline JSON index: $err');
      db.execute('INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)', ['json_migrated', '1']);
    }
  }

  void _ensureColumn(Database db, String tableName, String columnName, String definition) {
    final columns = db.select('PRAGMA table_info($tableName)');
    final exists = columns.any((row) => OfflineLibraryStorage._readString(row, 'name') == columnName);

    if (!exists) {
      db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $definition');
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineSchemaFacade {
  _OfflineSchema get _ownerSchema;

  bool _metadataTableExists(Database db) => _ownerSchema._metadataTableExists(db);

  int _readStoredSchemaVersion(Database db) => _ownerSchema._readStoredSchemaVersion(db);

  bool _metadataFlag(Database db, String key) => _ownerSchema._metadataFlag(db, key);

  void _initSchema(Database db) => _ownerSchema._initSchema(db);

  Future<void> _migrateJsonIndexIfNeeded(Database db) => _ownerSchema._migrateJsonIndexIfNeeded(db);
}
