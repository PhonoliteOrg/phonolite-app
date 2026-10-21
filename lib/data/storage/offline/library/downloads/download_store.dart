part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineDownloadStore {
  final OfflineLibraryStorage _host;

  _OfflineDownloadStore(this._host);

  Future<List<OfflineTrackDownload>> readDownloads() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readDownloads(db);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline library: $err');

        return const [];
      },
    );
  }

  Future<void> writeDownloads(List<OfflineTrackDownload> downloads) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          final existing = db.select('SELECT server_base_url, server_track_id FROM source_tracks');
          final nextKeys = downloads
              .map(
                (item) =>
                    OfflineLibraryStorage._sourceKey(item.serverBaseUrl, item.track.serverTrackId ?? item.track.id),
              )
              .toSet();

          for (final row in existing) {
            final key = OfflineLibraryStorage._sourceKey(
              OfflineLibraryStorage._readString(row, 'server_base_url'),
              OfflineLibraryStorage._readString(row, 'server_track_id'),
            );

            if (!nextKeys.contains(key)) {
              db.execute('DELETE FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?', [
                OfflineLibraryStorage._readString(row, 'server_base_url'),
                OfflineLibraryStorage._readString(row, 'server_track_id'),
              ]);
              db.execute('DELETE FROM download_items WHERE server_base_url = ? AND server_track_id = ?', [
                OfflineLibraryStorage._readString(row, 'server_base_url'),
                OfflineLibraryStorage._readString(row, 'server_track_id'),
              ]);
              db.execute('DELETE FROM offline_metadata_fragments WHERE server_base_url = ? AND server_track_id = ?', [
                OfflineLibraryStorage._readString(row, 'server_base_url'),
                OfflineLibraryStorage._readString(row, 'server_track_id'),
              ]);
            }
          }

          for (final download in downloads) {
            _upsertDownload(db, download);
          }

          _host._pruneUnavailableLocalUserData(db);
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline library: $err');
      },
    );
  }

  Future<OfflineTrackDownload> prepareDownload(OfflineTrackDownload download) async {
    if (kIsWeb) {
      return download;
    }

    return await _host._withDatabase(
      (db) {
        final localTrackId = _host._resolveLocalTrackId(db, download.track);

        return _host._withLocalTrack(download, localTrackId);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to prepare offline metadata: $err');

        return download;
      },
    );
  }

  Future<List<OfflineTrackDownload>> prepareDownloads(List<OfflineTrackDownload> downloads) async {
    if (kIsWeb || downloads.isEmpty) {
      return downloads;
    }

    return await _host._withDatabase(
      (db) {
        return downloads
            .map((download) {
              final localTrackId = _host._resolveLocalTrackId(db, download.track);

              return _host._withLocalTrack(download, localTrackId);
            })
            .toList(growable: false);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to prepare offline metadata batch: $err');

        return downloads;
      },
    );
  }

  Future<void> upsertDownload(OfflineTrackDownload download) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          _upsertDownload(db, download);
          _host._pruneUnavailableLocalUserData(db);
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to upsert offline download: $err');
      },
    );
  }

  Future<void> upsertDownloads(List<OfflineTrackDownload> downloads) async {
    if (kIsWeb || downloads.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final download in downloads) {
            _upsertDownload(db, download);
          }

          _host._pruneUnavailableLocalUserData(db);
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to upsert offline downloads: $err');
      },
    );
  }

  List<OfflineTrackDownload> _readDownloads(Database db) {
    final rows = db.select('''
      SELECT
        s.*,
        t.title,
        t.artist,
        t.artist_id,
        t.album,
        t.album_id,
        t.album_art_path,
        t.artist_art_path,
        t.artist_banner_path,
        t.genres_json,
        t.duration_ms,
        t.track_no,
        t.disc_no,
        f.schema_version AS offline_schema_version,
        f.track_json AS offline_track_json,
        f.album_json AS offline_album_json,
        f.artist_json AS offline_artist_json,
        EXISTS(SELECT 1 FROM local_likes l WHERE l.local_track_id = t.id) AS local_liked,
        EXISTS(SELECT 1 FROM local_playlist_tracks pt WHERE pt.local_track_id = t.id) AS local_in_playlists
      FROM source_tracks s
      JOIN tracks t ON t.id = s.local_track_id
      LEFT JOIN offline_metadata_fragments f
        ON f.server_base_url = s.server_base_url
       AND f.server_track_id = s.server_track_id
      ORDER BY s.updated_at DESC
    ''');

    return rows.map(_host._downloadFromRow).toList(growable: false);
  }

  void _upsertDownload(Database db, OfflineTrackDownload download) {
    final localTrackId = download.localTrackId?.trim().isNotEmpty == true
        ? download.localTrackId!
        : _host._resolveLocalTrackId(db, download.track);
    final normalized = _host._withLocalTrack(download, localTrackId);

    _host._upsertTrack(db, localTrackId, normalized.track);
    _host._upsertOfflineMetadataFragment(db, normalized, localTrackId);

    db.execute(
      '''
      INSERT INTO source_tracks (
        server_base_url,
        server_track_id,
        local_track_id,
        batch_id,
        download_url,
        status,
        created_at,
        updated_at,
        file_path,
        partial_path,
        bytes_downloaded,
        bytes_total,
        etag,
        expected_sha256,
        content_type,
        error,
        retry_count,
        priority
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        local_track_id = excluded.local_track_id,
        batch_id = excluded.batch_id,
        download_url = excluded.download_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        file_path = excluded.file_path,
        partial_path = excluded.partial_path,
        bytes_downloaded = excluded.bytes_downloaded,
        bytes_total = excluded.bytes_total,
        etag = excluded.etag,
        expected_sha256 = excluded.expected_sha256,
        content_type = excluded.content_type,
        error = excluded.error,
        retry_count = excluded.retry_count,
        priority = excluded.priority
    ''',
      [
        normalized.serverBaseUrl,
        normalized.track.serverTrackId ?? normalized.track.id,
        localTrackId,
        normalized.batchId,
        normalized.downloadUrl,
        normalized.status.name,
        normalized.createdAt.millisecondsSinceEpoch,
        normalized.updatedAt.millisecondsSinceEpoch,
        normalized.filePath,
        normalized.partialPath,
        normalized.bytesDownloaded,
        normalized.bytesTotal,
        normalized.etag,
        normalized.expectedSha256,
        normalized.contentType,
        normalized.error,
        normalized.retryCount,
        normalized.priority,
      ],
    );

    db.execute(
      '''
      INSERT INTO download_items (
        server_base_url,
        server_track_id,
        batch_id,
        local_track_id,
        status,
        created_at,
        updated_at,
        file_path,
        partial_path,
        bytes_downloaded,
        bytes_total,
        etag,
        expected_sha256,
        content_type,
        error,
        retry_count,
        priority
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(server_base_url, server_track_id) DO UPDATE SET
        batch_id = excluded.batch_id,
        local_track_id = excluded.local_track_id,
        status = excluded.status,
        updated_at = excluded.updated_at,
        file_path = excluded.file_path,
        partial_path = excluded.partial_path,
        bytes_downloaded = excluded.bytes_downloaded,
        bytes_total = excluded.bytes_total,
        etag = excluded.etag,
        expected_sha256 = excluded.expected_sha256,
        content_type = excluded.content_type,
        error = excluded.error,
        retry_count = excluded.retry_count,
        priority = excluded.priority
    ''',
      [
        normalized.serverBaseUrl,
        normalized.track.serverTrackId ?? normalized.track.id,
        normalized.batchId,
        localTrackId,
        normalized.status.name,
        normalized.createdAt.millisecondsSinceEpoch,
        normalized.updatedAt.millisecondsSinceEpoch,
        normalized.filePath,
        normalized.partialPath,
        normalized.bytesDownloaded,
        normalized.bytesTotal,
        normalized.etag,
        normalized.expectedSha256,
        normalized.contentType,
        normalized.error,
        normalized.retryCount,
        normalized.priority,
      ],
    );

    if (normalized.status == OfflineDownloadStatus.downloaded && normalized.filePath != null) {
      _host._resolvePendingPlaylistTracks(
        db,
        serverBaseUrl: normalized.serverBaseUrl,
        serverTrackId: normalized.track.serverTrackId ?? normalized.track.id,
      );
    }
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineDownloadStoreFacade {
  _OfflineDownloadStore get _ownerDownloads;

  Future<List<OfflineTrackDownload>> readDownloads() => _ownerDownloads.readDownloads();

  Future<void> writeDownloads(List<OfflineTrackDownload> downloads) => _ownerDownloads.writeDownloads(downloads);

  Future<OfflineTrackDownload> prepareDownload(OfflineTrackDownload download) =>
      _ownerDownloads.prepareDownload(download);

  Future<List<OfflineTrackDownload>> prepareDownloads(List<OfflineTrackDownload> downloads) =>
      _ownerDownloads.prepareDownloads(downloads);

  Future<void> upsertDownload(OfflineTrackDownload download) => _ownerDownloads.upsertDownload(download);

  Future<void> upsertDownloads(List<OfflineTrackDownload> downloads) => _ownerDownloads.upsertDownloads(downloads);

  List<OfflineTrackDownload> _readDownloads(Database db) => _ownerDownloads._readDownloads(db);

  void _upsertDownload(Database db, OfflineTrackDownload download) => _ownerDownloads._upsertDownload(db, download);
}
