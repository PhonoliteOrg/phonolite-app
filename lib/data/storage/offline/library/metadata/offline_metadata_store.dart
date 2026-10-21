part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineMetadataStore {
  final OfflineLibraryStorage _host;

  _OfflineMetadataStore(this._host);

  Future<String> readOrCreateClientId() async {
    if (kIsWeb) {
      return 'web';
    }

    final db = await _host._openDatabase();

    try {
      final rows = db.select('SELECT value FROM client_identity WHERE key = ? LIMIT 1', ['client_id']);

      if (rows.isNotEmpty) {
        final existing = rows.first['value']?.toString().trim();

        if (existing != null && existing.isNotEmpty) {
          return existing;
        }
      }

      final clientId = _host._generateClientId();

      db.execute('INSERT OR REPLACE INTO client_identity (key, value, updated_at) VALUES (?, ?, ?)', [
        'client_id',
        clientId,
        DateTime.now().millisecondsSinceEpoch,
      ]);

      return clientId;
    } finally {
      _host._releaseDatabase(db);
    }
  }

  Future<void> updateTrackArtPaths(
    String localTrackId, {
    String? albumArtPath,
    String? artistArtPath,
    String? artistBannerPath,
    Track? artworkSource,
  }) async {
    if (kIsWeb) {
      return;
    }

    if (albumArtPath == null && artistArtPath == null && artistBannerPath == null) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        final artistIdentity = artworkSource?.artistArtworkIdentity;

        db.execute(
          '''
        UPDATE tracks
        SET album_art_path = COALESCE(?, album_art_path),
            artist_art_path = CASE
              WHEN ? IS NULL OR COALESCE(
                'id:' || NULLIF(TRIM(artist_id), ''),
                'name:' || LOWER(TRIM(artist))
              ) = ? THEN COALESCE(?, artist_art_path)
              ELSE artist_art_path END,
            artist_banner_path = CASE
              WHEN ? IS NULL OR COALESCE(
                'id:' || NULLIF(TRIM(artist_id), ''),
                'name:' || LOWER(TRIM(artist))
              ) = ? THEN COALESCE(?, artist_banner_path)
              ELSE artist_banner_path END,
            updated_at = ?
        WHERE id = ?
      ''',
          [
            albumArtPath,
            artistIdentity,
            artistIdentity,
            artistArtPath,
            artistIdentity,
            artistIdentity,
            artistBannerPath,
            DateTime.now().millisecondsSinceEpoch,
            localTrackId,
          ],
        );
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to update offline artwork metadata: $err');
      },
    );
  }

  Future<List<Track>> readLocalDownloadedTracks() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readLocalTracks(db, whereDownloaded: true);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read local downloaded tracks: $err');

        return const [];
      },
    );
  }

  Future<List<OfflineMetadataRepairRequest>> readMetadataRepairRequests(String serverBaseUrl, {int limit = 32}) async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        final rows = db.select(
          '''
        SELECT s.server_base_url, s.server_track_id
        FROM source_tracks s
        LEFT JOIN offline_metadata_fragments f
          ON f.server_base_url = s.server_base_url
         AND f.server_track_id = s.server_track_id
        WHERE s.server_base_url = ?
          AND s.status = ?
          AND s.file_path IS NOT NULL
          AND (
            f.schema_version IS NULL
            OR f.schema_version < ?
            OR f.track_json IS NULL
            OR f.album_json IS NULL
            OR f.artist_json IS NULL
            OR trim(f.track_json) = ''
            OR trim(f.album_json) = ''
            OR trim(f.artist_json) = ''
            OR json_valid(f.track_json) = 0
            OR json_valid(f.album_json) = 0
            OR json_valid(f.artist_json) = 0
          )
        ORDER BY s.updated_at DESC
        LIMIT ?
      ''',
          [serverBaseUrl, OfflineDownloadStatus.downloaded.name, OfflineTrackMetadata.currentSchemaVersion, limit],
        );

        return rows
            .map(
              (row) => OfflineMetadataRepairRequest(
                serverBaseUrl: OfflineLibraryStorage._readString(row, 'server_base_url'),
                serverTrackId: OfflineLibraryStorage._readString(row, 'server_track_id'),
              ),
            )
            .toList(growable: false);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline metadata repair queue: $err');

        return const [];
      },
    );
  }

  Future<void> upsertOfflineMetadataFragment(
    String serverBaseUrl,
    String serverTrackId,
    OfflineTrackMetadata metadata,
  ) async {
    await _host.upsertOfflineMetadataFragments(serverBaseUrl, {serverTrackId: metadata});
  }

  /// Persist one fetched chunk atomically, retaining each server's source IDs.
  /// The guard runs after opening the database and immediately before writes.
  Future<Set<String>> upsertOfflineMetadataFragments(
    String serverBaseUrl,
    Map<String, OfflineTrackMetadata> metadataByTrackId, {
    bool Function()? shouldPersist,
  }) async {
    if (kIsWeb || metadataByTrackId.isEmpty) {
      return const <String>{};
    }

    return await _host._withDatabase((db) {
      if (shouldPersist != null && !shouldPersist()) {
        return const <String>{};
      }

      final persisted = <String>{};

      _host._transaction(db, () {
        for (final entry in metadataByTrackId.entries) {
          final serverTrackId = entry.key;
          final metadata = entry.value;
          final rows = db.select(
            '''
            SELECT local_track_id
            FROM source_tracks
            WHERE server_base_url = ?
              AND server_track_id = ?
            LIMIT 1
          ''',
            [serverBaseUrl, serverTrackId],
          );

          if (rows.isEmpty) {
            continue;
          }

          final localTrackId = OfflineLibraryStorage._readString(rows.first, 'local_track_id');
          final track = metadata.track.copyWith(
            id: serverTrackId,
            localId: localTrackId,
            serverBaseUrl: serverBaseUrl,
            serverTrackId: serverTrackId,
          );

          _host._upsertTrack(db, localTrackId, track);
          _upsertOfflineMetadataFragmentRaw(
            db,
            serverBaseUrl: serverBaseUrl,
            serverTrackId: serverTrackId,
            localTrackId: localTrackId,
            metadata: metadata.copyWith(track: track),
          );
          persisted.add(serverTrackId);
        }
      });

      return persisted;
    });
  }

  Future<void> _deleteOfflineMetadataFiles(Directory metadataDir) async {
    for (final fileName in [
      OfflineLibraryStorage._databaseFileName,
      '${OfflineLibraryStorage._databaseFileName}-wal',
      '${OfflineLibraryStorage._databaseFileName}-shm',
      '${OfflineLibraryStorage._databaseFileName}-journal',
      OfflineLibraryStorage._indexFileName,
    ]) {
      await _host._deleteFileIfExists(File(_host._join(metadataDir.path, fileName)));
    }

    await _host._deleteDirectoryIfExists(Directory(_host._join(metadataDir.path, OfflineLibraryStorage._artDirName)));
  }

  List<Track> _readLocalTracks(Database db, {required bool whereDownloaded}) {
    final downloaded = OfflineDownloadStatus.downloaded.name;
    final rows = db.select(
      '''
      SELECT
        t.*,
        s.server_base_url,
        s.server_track_id,
        (
          SELECT f.schema_version
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_schema_version,
        (
          SELECT f.track_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_track_json,
        (
          SELECT f.album_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_album_json,
        (
          SELECT f.artist_json
          FROM offline_metadata_fragments f
          JOIN source_tracks fs
            ON fs.server_base_url = f.server_base_url
           AND fs.server_track_id = f.server_track_id
          WHERE f.local_track_id = t.id
            AND fs.status = ?
            AND fs.file_path IS NOT NULL
          ORDER BY fs.updated_at DESC
          LIMIT 1
        ) AS offline_artist_json
      FROM tracks t
      LEFT JOIN source_tracks s ON s.local_track_id = t.id
        AND s.status = ?
        AND s.file_path IS NOT NULL
      ${whereDownloaded ? '''
      WHERE EXISTS (
        SELECT 1 FROM source_tracks ds
        WHERE ds.local_track_id = t.id
          AND ds.status = ?
          AND ds.file_path IS NOT NULL
      )
      ''' : ''}
      GROUP BY t.id
      ORDER BY t.artist, t.album, t.disc_no, t.track_no, t.title
    ''',
      whereDownloaded
          ? [downloaded, downloaded, downloaded, downloaded, downloaded, downloaded]
          : [downloaded, downloaded, downloaded, downloaded, downloaded],
    );

    return rows
        .map((row) {
          final localId = OfflineLibraryStorage._readString(row, 'id');

          return _host._trackFromRow(
            row,
            liked: _host._trackIsLocallyLiked(db, localId),
            inPlaylists: _host._trackInLocalPlaylists(db, localId),
          );
        })
        .toList(growable: false);
  }

  void _upsertOfflineMetadataFragment(Database db, OfflineTrackDownload download, String localTrackId) {
    final metadata = download.offlineMetadata;
    if (metadata == null) {
      return;
    }

    final serverTrackId = OfflineLibraryStorage._serverTrackId(download);
    final sameArtist = download.track.artistArtworkIdentity == metadata.track.artistArtworkIdentity;
    final track = metadata.track.copyWith(
      id: serverTrackId,
      localId: localTrackId,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      albumArtPath: download.track.albumArtPath ?? metadata.track.albumArtPath,
      artistArtPath: (sameArtist ? download.track.artistArtPath : null) ?? metadata.track.artistArtPath,
      artistBannerPath: (sameArtist ? download.track.artistBannerPath : null) ?? metadata.track.artistBannerPath,
      liked: download.track.liked,
      inPlaylists: download.track.inPlaylists,
    );

    final normalized = metadata.copyWith(track: track);

    _upsertOfflineMetadataFragmentRaw(
      db,
      serverBaseUrl: download.serverBaseUrl,
      serverTrackId: serverTrackId,
      localTrackId: localTrackId,
      metadata: normalized,
    );
  }

  void _upsertOfflineMetadataFragmentRaw(
    Database db, {
    required String serverBaseUrl,
    required String serverTrackId,
    required String localTrackId,
    required OfflineTrackMetadata metadata,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    db.execute(
      '''
      INSERT INTO offline_metadata_fragments (
        server_base_url,
        server_track_id,
        local_track_id,
        schema_version,
        track_json,
        album_json,
        artist_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        local_track_id = excluded.local_track_id,
        schema_version = excluded.schema_version,
        track_json = excluded.track_json,
        album_json = excluded.album_json,
        artist_json = excluded.artist_json,
        updated_at = excluded.updated_at
    ''',
      [
        serverBaseUrl,
        serverTrackId,
        localTrackId,
        metadata.schemaVersion,
        jsonEncode(metadata.track.copyWith(offlineArtists: metadata.allArtists).toJson()),
        jsonEncode(metadata.album.toJson()),
        jsonEncode(metadata.artist.toJson()),
        now,
        now,
      ],
    );
  }

  void _upsertTrack(Database db, String localTrackId, Track track) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final matchKey = OfflineLibraryStorage._metadataMatchKey(track);

    db.execute(
      '''
      INSERT INTO tracks (
        id,
        match_key,
        title,
        artist,
        artist_id,
        album,
        album_id,
        album_art_path,
        artist_art_path,
        artist_banner_path,
        genres_json,
        duration_ms,
        track_no,
        disc_no,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        match_key = excluded.match_key,
        title = excluded.title,
        artist = excluded.artist,
        artist_id = excluded.artist_id,
        album = excluded.album,
        album_id = excluded.album_id,
        album_art_path = COALESCE(excluded.album_art_path, album_art_path),
        artist_art_path = CASE
          WHEN COALESCE(
            'id:' || NULLIF(TRIM(artist_id), ''),
            'name:' || LOWER(TRIM(artist))
          ) = COALESCE(
            'id:' || NULLIF(TRIM(excluded.artist_id), ''),
            'name:' || LOWER(TRIM(excluded.artist))
          ) THEN COALESCE(excluded.artist_art_path, artist_art_path)
          ELSE excluded.artist_art_path END,
        artist_banner_path = CASE
          WHEN COALESCE(
            'id:' || NULLIF(TRIM(artist_id), ''),
            'name:' || LOWER(TRIM(artist))
          ) = COALESCE(
            'id:' || NULLIF(TRIM(excluded.artist_id), ''),
            'name:' || LOWER(TRIM(excluded.artist))
          ) THEN COALESCE(excluded.artist_banner_path, artist_banner_path)
          ELSE excluded.artist_banner_path END,
        genres_json = excluded.genres_json,
        duration_ms = excluded.duration_ms,
        track_no = excluded.track_no,
        disc_no = excluded.disc_no,
        updated_at = excluded.updated_at
    ''',
      [
        localTrackId,
        matchKey,
        track.title,
        track.artist,
        track.artistId,
        track.album,
        track.albumId,
        track.albumArtPath,
        track.artistArtPath,
        track.artistBannerPath,
        jsonEncode(track.genres),
        track.durationMs,
        track.trackNo,
        track.discNo,
        now,
        now,
      ],
    );
  }

  String _resolveLocalTrackId(Database db, Track track) {
    final matchKey = OfflineLibraryStorage._metadataMatchKey(track);
    final rows = db.select('SELECT id, duration_ms FROM tracks WHERE match_key = ?', [matchKey]);

    for (final row in rows) {
      final duration = OfflineLibraryStorage._readInt(row, 'duration_ms');

      if ((duration - track.durationMs).abs() <= 2000) {
        final id = OfflineLibraryStorage._readString(row, 'id');

        _host._upsertTrack(db, id, track);

        return id;
      }
    }

    var id = OfflineLibraryStorage._stableId('$matchKey|${track.durationMs}');
    var suffix = 1;

    while (db.select('SELECT id FROM tracks WHERE id = ?', [id]).isNotEmpty) {
      id = OfflineLibraryStorage._stableId('$matchKey|${track.durationMs}|$suffix');
      suffix += 1;
    }

    _host._upsertTrack(db, id, track);

    return id;
  }

  void _requireDownloadedLocalTrack(Database db, String localTrackId) {
    final rows = db.select(
      '''
      SELECT file_path FROM source_tracks
      WHERE local_track_id = ?
        AND status = ?
        AND file_path IS NOT NULL
    ''',
      [localTrackId, OfflineDownloadStatus.downloaded.name],
    );

    for (final row in rows) {
      final filePath = OfflineLibraryStorage._readNullableString(row, 'file_path');

      if (filePath != null && File(filePath).existsSync()) {
        return;
      }
    }

    throw StateError('Track must be downloaded before saving local user data.');
  }

  static String _metadataMatchKey(Track track) {
    return [
      OfflineLibraryStorage._normalizeMetadataText(track.artist),
      OfflineLibraryStorage._normalizeMetadataText(track.album),
      OfflineLibraryStorage._normalizeMetadataText(track.title),
    ].join('|');
  }

  String _generateClientId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final suffix = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    return 'client-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  static String _stableId(String value) {
    final encoded = base64Url.encode(utf8.encode(value)).replaceAll('=', '');

    return 'lt_$encoded';
  }

  static String _normalizeMetadataText(String value) {
    final out = StringBuffer();
    var lastSpace = false;

    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      final isAlphaNumeric = (codeUnit >= 48 && codeUnit <= 57) || (codeUnit >= 97 && codeUnit <= 122);

      if (isAlphaNumeric) {
        out.writeCharCode(codeUnit);
        lastSpace = false;
      } else if (!lastSpace) {
        out.write(' ');
        lastSpace = true;
      }
    }

    return out.toString().trim();
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineMetadataStoreFacade {
  _OfflineMetadataStore get _ownerMetadata;

  Future<String> readOrCreateClientId() => _ownerMetadata.readOrCreateClientId();

  Future<void> updateTrackArtPaths(
    String localTrackId, {
    String? albumArtPath,
    String? artistArtPath,
    String? artistBannerPath,
    Track? artworkSource,
  }) => _ownerMetadata.updateTrackArtPaths(
    localTrackId,
    albumArtPath: albumArtPath,
    artistArtPath: artistArtPath,
    artistBannerPath: artistBannerPath,
    artworkSource: artworkSource,
  );

  Future<List<Track>> readLocalDownloadedTracks() => _ownerMetadata.readLocalDownloadedTracks();

  Future<List<OfflineMetadataRepairRequest>> readMetadataRepairRequests(String serverBaseUrl, {int limit = 32}) =>
      _ownerMetadata.readMetadataRepairRequests(serverBaseUrl, limit: limit);

  Future<void> upsertOfflineMetadataFragment(
    String serverBaseUrl,
    String serverTrackId,
    OfflineTrackMetadata metadata,
  ) => _ownerMetadata.upsertOfflineMetadataFragment(serverBaseUrl, serverTrackId, metadata);

  /// Persist one fetched chunk atomically, retaining each server's source IDs.
  /// The guard runs after opening the database and immediately before writes.
  Future<Set<String>> upsertOfflineMetadataFragments(
    String serverBaseUrl,
    Map<String, OfflineTrackMetadata> metadataByTrackId, {
    bool Function()? shouldPersist,
  }) => _ownerMetadata.upsertOfflineMetadataFragments(serverBaseUrl, metadataByTrackId, shouldPersist: shouldPersist);

  Future<void> _deleteOfflineMetadataFiles(Directory metadataDir) =>
      _ownerMetadata._deleteOfflineMetadataFiles(metadataDir);

  void _upsertOfflineMetadataFragment(Database db, OfflineTrackDownload download, String localTrackId) =>
      _ownerMetadata._upsertOfflineMetadataFragment(db, download, localTrackId);

  void _upsertTrack(Database db, String localTrackId, Track track) =>
      _ownerMetadata._upsertTrack(db, localTrackId, track);

  String _generateClientId() => _ownerMetadata._generateClientId();

  String _resolveLocalTrackId(Database db, Track track) => _ownerMetadata._resolveLocalTrackId(db, track);

  void _requireDownloadedLocalTrack(Database db, String localTrackId) =>
      _ownerMetadata._requireDownloadedLocalTrack(db, localTrackId);
}
