part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _LocalPlaylistStore {
  final OfflineLibraryStorage _host;

  _LocalPlaylistStore(this._host);

  Future<List<Playlist>> readLocalPlaylists() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readLocalPlaylists(db);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read local playlists: $err');

        return const [];
      },
    );
  }

  Future<List<Track>> readLocalPlaylistTracks(String playlistId) async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        final rows = db.select(
          '''
        SELECT t.*, s.server_base_url, s.server_track_id
        FROM local_playlist_tracks pt
        JOIN tracks t ON t.id = pt.local_track_id
        LEFT JOIN source_tracks s ON s.local_track_id = t.id
          AND s.status = ?
          AND s.file_path IS NOT NULL
        WHERE pt.playlist_id = ?
          AND EXISTS (
            SELECT 1 FROM source_tracks ds
            WHERE ds.local_track_id = t.id
              AND ds.status = ?
              AND ds.file_path IS NOT NULL
          )
        GROUP BY pt.rowid
        ORDER BY pt.position, pt.rowid
      ''',
          [OfflineDownloadStatus.downloaded.name, playlistId, OfflineDownloadStatus.downloaded.name],
        );

        return rows
            .map(
              (row) => _host._trackFromRow(
                row,
                liked: _host._trackIsLocallyLiked(db, OfflineLibraryStorage._readString(row, 'id')),
                inPlaylists: true,
              ),
            )
            .toList(growable: false);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read local playlist tracks: $err');

        return const [];
      },
    );
  }

  Future<Playlist> createLocalPlaylist(
    String name, {
    String? description,
    String? downloadServerBaseUrl,
    List<String> downloadTrackIds = const [],
  }) async {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('name is required');
    }

    if (downloadTrackIds.isNotEmpty &&
        (downloadServerBaseUrl == null ||
            downloadServerBaseUrl.trim().isEmpty ||
            downloadTrackIds.any((id) => id.trim().isEmpty))) {
      throw ArgumentError('Playlist download sources must be specified.');
    }

    final trimmedDescription = OfflineLibraryStorage._normalizeOptionalText(description);

    return await _host._withDatabase((db) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = OfflineLibraryStorage._stableId('playlist|$trimmed|$now');

      _host._transaction(db, () {
        db.execute(
          'INSERT INTO local_playlists (id, name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [id, trimmed, trimmedDescription, now, now],
        );

        for (var position = 0; position < downloadTrackIds.length; position++) {
          db.execute(
            'INSERT INTO pending_playlist_tracks (playlist_id, position, server_base_url, server_track_id) VALUES (?, ?, ?, ?)',
            [id, position, downloadServerBaseUrl, downloadTrackIds[position]],
          );
        }

        _resolvePendingPlaylistTracks(db);
      });

      return _readLocalPlaylists(db).firstWhere((playlist) => playlist.id == id);
    });
  }

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) async {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('name is required');
    }

    final trimmedDescription = OfflineLibraryStorage._normalizeOptionalText(description);

    return await _host._withDatabase((db) {
      final now = DateTime.now().millisecondsSinceEpoch;

      _host._transaction(db, () {
        db.execute('UPDATE local_playlists SET name = ?, description = ?, updated_at = ? WHERE id = ?', [
          trimmed,
          trimmedDescription,
          now,
          playlistId,
        ]);
      });

      final playlists = _readLocalPlaylists(db);

      for (final playlist in playlists) {
        if (playlist.id == playlistId) {
          return playlist;
        }
      }

      return null;
    });
  }

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) async {
    if (imageEdit.kind == PlaylistImageEditKind.keep) {
      return await _host._withDatabase((db) {
        return _readLocalPlaylists(db).where((item) => item.id == playlistId).firstOrNull;
      });
    }

    String? nextPath;

    if (imageEdit.kind == PlaylistImageEditKind.replace) {
      final bytes = imageEdit.bytes;

      if (bytes == null || bytes.isEmpty) {
        throw ArgumentError('image bytes are required');
      }

      final extension = OfflineLibraryStorage.extensionFromImageContentType(imageEdit.contentType);
      final file = await _host.playlistArtFile(playlistId: playlistId, extension: extension);

      await file.writeAsBytes(bytes, flush: true);
      nextPath = file.absolute.path;
    }

    Database? db;
    String? oldPath;
    var playlistExists = false;

    try {
      db = await _host._openDatabase();
      _host._transaction(db, () {
        final rows = db!.select('SELECT image_path FROM local_playlists WHERE id = ?', [playlistId]);

        if (rows.isEmpty) {
          return;
        }

        playlistExists = true;
        oldPath = OfflineLibraryStorage._readNullableString(rows.first, 'image_path');
        db.execute('UPDATE local_playlists SET image_path = ?, updated_at = ? WHERE id = ?', [
          nextPath,
          DateTime.now().millisecondsSinceEpoch,
          playlistId,
        ]);
      });

      if (!playlistExists) {
        if (nextPath != null) {
          await _host._deleteFileIfExists(File(nextPath));
        }

        return null;
      }

      if (oldPath != null && oldPath != nextPath) {
        await _host._deleteFileIfExists(File(oldPath!));
      }

      return _readLocalPlaylists(db).where((item) => item.id == playlistId).firstOrNull;
    } finally {
      _host._releaseDatabase(db);
    }
  }

  Future<void> deleteLocalPlaylist(String playlistId) async {
    Database? db;
    String? imagePath;

    try {
      db = await _host._openDatabase();
      final rows = db.select('SELECT image_path FROM local_playlists WHERE id = ?', [playlistId]);

      if (rows.isNotEmpty) {
        imagePath = OfflineLibraryStorage._readNullableString(rows.first, 'image_path');
      }

      _host._transaction(db, () {
        db!.execute('DELETE FROM local_playlist_tracks WHERE playlist_id = ?', [playlistId]);
        db.execute('DELETE FROM local_playlists WHERE id = ?', [playlistId]);
      });

      if (imagePath != null) {
        await _host._deleteFileIfExists(File(imagePath));
      }
    } finally {
      _host._releaseDatabase(db);
    }
  }

  Future<Playlist?> addLocalTrackToPlaylist(String playlistId, String localTrackId) async {
    return await _host._withDatabase((db) {
      _host._requireDownloadedLocalTrack(db, localTrackId);
      _host._transaction(db, () {
        final exists = db.select('SELECT 1 FROM local_playlist_tracks WHERE playlist_id = ? AND local_track_id = ?', [
          playlistId,
          localTrackId,
        ]);

        if (exists.isNotEmpty) {
          return;
        }

        final position =
            db
                    .select(
                      '''SELECT COALESCE(MAX(position), -1) + 1 AS next_position FROM (
            SELECT position FROM local_playlist_tracks WHERE playlist_id = ?
            UNION ALL
            SELECT position FROM pending_playlist_tracks WHERE playlist_id = ?
          )''',
                      [playlistId, playlistId],
                    )
                    .first['next_position']
                as int;

        db.execute(
          'INSERT OR IGNORE INTO local_playlist_tracks (playlist_id, local_track_id, position) VALUES (?, ?, ?)',
          [playlistId, localTrackId, position],
        );
        db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [
          DateTime.now().millisecondsSinceEpoch,
          playlistId,
        ]);
      });

      return _readLocalPlaylists(db).where((item) => item.id == playlistId).firstOrNull;
    });
  }

  Future<Playlist?> removeLocalTrackFromPlaylist(String playlistId, String localTrackId) async {
    return await _host._withDatabase((db) {
      _host._transaction(db, () {
        db.execute('DELETE FROM local_playlist_tracks WHERE playlist_id = ? AND local_track_id = ?', [
          playlistId,
          localTrackId,
        ]);
        db.execute('UPDATE local_playlists SET updated_at = ? WHERE id = ?', [
          DateTime.now().millisecondsSinceEpoch,
          playlistId,
        ]);
      });

      return _readLocalPlaylists(db).where((item) => item.id == playlistId).firstOrNull;
    });
  }

  List<Playlist> _readLocalPlaylists(Database db) {
    final playlistRows = db.select(
      'SELECT id, name, description, image_path FROM local_playlists ORDER BY updated_at DESC, name',
    );
    final playlists = <Playlist>[];

    for (final row in playlistRows) {
      final playlistId = OfflineLibraryStorage._readString(row, 'id');
      final trackRows = db.select(
        'SELECT local_track_id FROM local_playlist_tracks WHERE playlist_id = ? ORDER BY position, rowid',
        [playlistId],
      );

      playlists.add(
        Playlist(
          id: playlistId,
          name: OfflineLibraryStorage._readString(row, 'name'),
          trackIds: trackRows
              .map((item) => OfflineLibraryStorage._readString(item, 'local_track_id'))
              .toList(growable: false),
          description: OfflineLibraryStorage._readNullableString(row, 'description'),
          imagePath: OfflineLibraryStorage._readNullableString(row, 'image_path'),
        ),
      );
    }

    return playlists;
  }

  void _resolvePendingPlaylistTracks(Database db, {String? serverBaseUrl, String? serverTrackId}) {
    final rows = db.select(
      '''SELECT p.playlist_id, p.position, s.local_track_id
        FROM pending_playlist_tracks p
        JOIN source_tracks s ON s.server_base_url = p.server_base_url
          AND s.server_track_id = p.server_track_id
        WHERE s.status = ? AND s.file_path IS NOT NULL
        ${serverBaseUrl == null ? '' : 'AND p.server_base_url = ? AND p.server_track_id = ?'}''',
      [
        OfflineDownloadStatus.downloaded.name,
        if (serverBaseUrl != null) ...[serverBaseUrl, serverTrackId],
      ],
    );

    for (final row in rows) {
      db.execute(
        'INSERT OR IGNORE INTO local_playlist_tracks (playlist_id, position, local_track_id) VALUES (?, ?, ?)',
        [row['playlist_id'], row['position'], row['local_track_id']],
      );
      db.execute('DELETE FROM pending_playlist_tracks WHERE playlist_id = ? AND position = ?', [
        row['playlist_id'],
        row['position'],
      ]);
    }
  }

  bool _trackInLocalPlaylists(Database db, String localTrackId) {
    return db.select('SELECT 1 FROM local_playlist_tracks WHERE local_track_id = ? LIMIT 1', [localTrackId]).isNotEmpty;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LocalPlaylistStoreFacade {
  _LocalPlaylistStore get _ownerPlaylists;

  Future<List<Playlist>> readLocalPlaylists() => _ownerPlaylists.readLocalPlaylists();

  Future<List<Track>> readLocalPlaylistTracks(String playlistId) => _ownerPlaylists.readLocalPlaylistTracks(playlistId);

  Future<Playlist> createLocalPlaylist(
    String name, {
    String? description,
    String? downloadServerBaseUrl,
    List<String> downloadTrackIds = const [],
  }) => _ownerPlaylists.createLocalPlaylist(
    name,
    description: description,
    downloadServerBaseUrl: downloadServerBaseUrl,
    downloadTrackIds: downloadTrackIds,
  );

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) =>
      _ownerPlaylists.renameLocalPlaylist(playlistId, name, description: description);

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) =>
      _ownerPlaylists.updateLocalPlaylistImage(playlistId, imageEdit);

  Future<void> deleteLocalPlaylist(String playlistId) => _ownerPlaylists.deleteLocalPlaylist(playlistId);

  Future<Playlist?> addLocalTrackToPlaylist(String playlistId, String localTrackId) =>
      _ownerPlaylists.addLocalTrackToPlaylist(playlistId, localTrackId);

  Future<Playlist?> removeLocalTrackFromPlaylist(String playlistId, String localTrackId) =>
      _ownerPlaylists.removeLocalTrackFromPlaylist(playlistId, localTrackId);

  void _resolvePendingPlaylistTracks(Database db, {String? serverBaseUrl, String? serverTrackId}) =>
      _ownerPlaylists._resolvePendingPlaylistTracks(db, serverBaseUrl: serverBaseUrl, serverTrackId: serverTrackId);

  bool _trackInLocalPlaylists(Database db, String localTrackId) =>
      _ownerPlaylists._trackInLocalPlaylists(db, localTrackId);
}
