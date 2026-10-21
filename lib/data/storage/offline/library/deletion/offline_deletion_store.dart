part of 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

class _OfflineDeletionStore {
  final OfflineLibraryStorage _host;

  _OfflineDeletionStore(this._host);

  Future<void> resetLocalData() async {
    if (kIsWeb) {
      return;
    }

    try {
      await _host.close();

      final locations = await _host.resolveStorageLocations();
      final metadataDir = Directory(locations.metadataDirectory);
      final downloadsDir = Directory(locations.downloadsDirectory);

      await _host._deleteOfflineMetadataFiles(metadataDir);
      await _host._deleteOfflineDownloadFiles(downloadsDir);
    } catch (err) {
      AppLogger.warning('Failed to reset offline storage: $err');

      rethrow;
    }
  }

  /// Remove unfinished plans and partial files without deleting downloaded songs
  /// or their library metadata, artwork, likes, and playlist memberships.
  Future<void> clearUnfinishedDownloads() async {
    if (kIsWeb) {
      return;
    }

    Database? db;

    try {
      final locations = await _host.resolveStorageLocations();
      final deleteRoots = await _host._managedDeleteRootPaths();

      db = await _host._openDatabase();

      late OfflineDeletionDraft draft;

      _host._transaction(db, () {
        draft = _removeDownloadsInTransaction(
          db!,
          const OfflineDeletionScope.track(),
          _host._readDownloads(db).where((download) => !download.isDownloaded).toList(growable: false),
          deleteRoots,
        );

        for (final table in ['download_jobs', 'download_batches']) {
          db.execute('DELETE FROM $table WHERE status != ?', [OfflineDownloadStatus.downloaded.name]);
        }
      });

      final retainedPaths = {
        for (final download in _host._readDownloads(db)) ...[
          if (download.filePath != null) File(download.filePath!).absolute.path,
          if (download.partialPath != null) File(download.partialPath!).absolute.path,
        ],
      };
      final pendingDeletes = {
        ...draft.pendingFileDeletes,
        ...await _host.readPendingFileDeletes(),
        ...await _host._unusedArtworkFiles(db, deleteRoots),
      };
      final downloadsDir = Directory(locations.downloadsDirectory);

      if (await downloadsDir.exists()) {
        await for (final directory in downloadsDir.list(followLinks: false)) {
          if (directory is! Directory || !directory.path.split(Platform.pathSeparator).last.startsWith('server_')) {
            continue;
          }

          await for (final file in directory.list(recursive: true, followLinks: false)) {
            if (file is File && file.path.endsWith('.${OfflineLibraryStorage._partialExtension}')) {
              pendingDeletes.add(file.absolute.path);
            }
          }
        }
      }

      pendingDeletes.removeAll(retainedPaths);
      _host._transaction(db, () {
        for (final path in retainedPaths) {
          db!.execute('DELETE FROM pending_file_deletes WHERE path = ?', [path]);
        }

        _host._recordPendingFileDeletes(
          db!,
          pendingDeletes,
          DateTime.now().millisecondsSinceEpoch,
          deleteRoots: deleteRoots,
        );
      });

      for (final path in pendingDeletes) {
        if (OfflineLibraryStorage._managedPendingDeletePath(path, deleteRoots) != null) {
          await _host._deleteFileIfExists(File(path));
        }
      }

      await _host.clearPendingFileDeletes(pendingDeletes);
    } finally {
      _host._releaseDatabase(db);
    }
  }

  Future<void> removeDownloads(Iterable<OfflineTrackDownload> downloads) async {
    await _host.removeDownloadsScoped(OfflineDeletionRequest.tracks(downloads));
  }

  Future<OfflineDeletionResult> removeDownloadsScoped(OfflineDeletionRequest request) async {
    if (kIsWeb) {
      return OfflineDeletionResult(scope: request.scope);
    }

    final byKey = <String, OfflineTrackDownload>{};

    for (final download in request.downloads) {
      byKey[OfflineLibraryStorage._sourceKey(download.serverBaseUrl, OfflineLibraryStorage._serverTrackId(download))] =
          download;
    }

    final removals = byKey.values.toList(growable: false);

    if (removals.isEmpty && request.downloadJobIds.isEmpty) {
      return OfflineDeletionResult(scope: request.scope);
    }

    Database? db;

    try {
      final deleteRoots = await _host._managedDeleteRootPaths();

      db = await _host._openDatabase();

      late OfflineDeletionDraft draft;

      _host._transaction(db, () {
        draft = _removeDownloadsInTransaction(db!, request.scope, removals, deleteRoots);

        for (final jobId in request.downloadJobIds) {
          db.execute('DELETE FROM download_jobs WHERE job_id = ?', [jobId]);
          db.execute('DELETE FROM download_batches WHERE batch_id = ?', [jobId]);
        }
      });

      final artworkDeletes = await _host._unusedArtworkFiles(db, deleteRoots);
      final pendingDeletes = <String>{...draft.pendingFileDeletes, ...artworkDeletes};

      if (pendingDeletes.isNotEmpty) {
        _host._transaction(db, () {
          _host._recordPendingFileDeletes(
            db!,
            pendingDeletes,
            DateTime.now().millisecondsSinceEpoch,
            deleteRoots: deleteRoots,
          );
        });
      }

      return draft.toResult(
        pendingFileDeleteCount: pendingDeletes.length,
        pendingArtworkDeleteCount: artworkDeletes.length,
      );
    } catch (err) {
      AppLogger.warning('Failed to remove offline downloads: $err');

      return OfflineDeletionResult(scope: request.scope);
    } finally {
      _host._releaseDatabase(db);
    }
  }

  OfflineDeletionDraft _removeDownloadsInTransaction(
    Database db,
    OfflineDeletionScope scope,
    List<OfflineTrackDownload> removals,
    List<String> deleteRoots,
  ) {
    final draft = OfflineDeletionDraft(scope: scope);
    final localTrackIds = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final download in removals) {
      final serverTrackId = OfflineLibraryStorage._serverTrackId(download);
      final rows = db.select(
        '''
        SELECT
          s.local_track_id,
          s.file_path,
          s.partial_path,
          t.album_art_path,
          t.artist_art_path,
          t.artist_banner_path
        FROM source_tracks s
        LEFT JOIN tracks t ON t.id = s.local_track_id
        WHERE s.server_base_url = ? AND s.server_track_id = ?
      ''',
        [download.serverBaseUrl, serverTrackId],
      );

      for (final row in rows) {
        localTrackIds.add(OfflineLibraryStorage._readString(row, 'local_track_id'));
        OfflineLibraryStorage._addPendingDeletePath(
          draft.pendingFileDeletes,
          OfflineLibraryStorage._readNullableString(row, 'file_path'),
          deleteRoots,
        );
        OfflineLibraryStorage._addPendingDeletePath(
          draft.pendingFileDeletes,
          OfflineLibraryStorage._readNullableString(row, 'partial_path'),
          deleteRoots,
        );
      }

      OfflineLibraryStorage._addPendingDeletePath(draft.pendingFileDeletes, download.filePath, deleteRoots);
      OfflineLibraryStorage._addPendingDeletePath(draft.pendingFileDeletes, download.partialPath, deleteRoots);

      draft.removedMetadataFragmentCount += db
          .select(
            '''
            SELECT 1
            FROM offline_metadata_fragments
            WHERE server_base_url = ? AND server_track_id = ?
          ''',
            [download.serverBaseUrl, serverTrackId],
          )
          .length;

      db.execute('DELETE FROM source_tracks WHERE server_base_url = ? AND server_track_id = ?', [
        download.serverBaseUrl,
        serverTrackId,
      ]);
      db.execute('DELETE FROM download_items WHERE server_base_url = ? AND server_track_id = ?', [
        download.serverBaseUrl,
        serverTrackId,
      ]);
      db.execute('DELETE FROM offline_metadata_fragments WHERE server_base_url = ? AND server_track_id = ?', [
        download.serverBaseUrl,
        serverTrackId,
      ]);

      final jobRows = db.select(
        '''
        SELECT i.job_id
        FROM download_job_items i
        JOIN download_jobs j ON j.job_id = i.job_id
        WHERE j.server_base_url = ?
          AND i.server_track_id = ?
          AND (i.track_json IS NOT NULL OR i.metadata_json IS NOT NULL)
      ''',
        [download.serverBaseUrl, serverTrackId],
      );

      draft.clearedJobMetadataCount += jobRows.length;
      db.execute(
        '''
        UPDATE download_job_items
        SET track_json = NULL,
            metadata_json = NULL,
            status = 'canceled',
            materialized = 1,
            error = NULL,
            updated_at = ?
        WHERE server_track_id = ?
          AND job_id IN (
            SELECT job_id FROM download_jobs WHERE server_base_url = ?
          )
      ''',
        [now, serverTrackId, download.serverBaseUrl],
      );

      draft.removedSourceCount += rows.isEmpty ? 0 : rows.length;
    }

    for (final localTrackId in localTrackIds) {
      final rows = db.select(
        '''
        SELECT id
        FROM tracks t
        WHERE t.id = ?
          AND NOT EXISTS (
            SELECT 1
            FROM source_tracks s
            WHERE s.local_track_id = t.id
          )
      ''',
        [localTrackId],
      );

      if (rows.isEmpty) {
        continue;
      }

      db.execute('DELETE FROM tracks WHERE id = ?', [localTrackId]);
      draft.removedLocalTrackCount += 1;
    }

    _pruneUnavailableLocalUserData(db);

    return draft;
  }

  Future<void> _runStartupGarbageCollection(Database db) async {
    final deleteRoots = await _host._managedDeleteRootPaths();
    final pendingDeletes = <String>{};

    _host._transaction(db, () {
      final orphanRows = db.select('''
        SELECT album_art_path, artist_art_path, artist_banner_path
        FROM tracks t
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.local_track_id = t.id
        )
      ''');

      for (final row in orphanRows) {
        OfflineLibraryStorage._addPendingDeletePath(
          pendingDeletes,
          OfflineLibraryStorage._readNullableString(row, 'album_art_path'),
          deleteRoots,
        );
        OfflineLibraryStorage._addPendingDeletePath(
          pendingDeletes,
          OfflineLibraryStorage._readNullableString(row, 'artist_art_path'),
          deleteRoots,
        );
        OfflineLibraryStorage._addPendingDeletePath(
          pendingDeletes,
          OfflineLibraryStorage._readNullableString(row, 'artist_banner_path'),
          deleteRoots,
        );
      }

      db.execute('''
        DELETE FROM tracks
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.local_track_id = tracks.id
        )
      ''');
      db.execute('''
        DELETE FROM offline_metadata_fragments
        WHERE NOT EXISTS (
          SELECT 1
          FROM source_tracks s
          WHERE s.server_base_url = offline_metadata_fragments.server_base_url
            AND s.server_track_id = offline_metadata_fragments.server_track_id
        )
      ''');
      db.execute(
        '''
        UPDATE download_job_items
        SET track_json = NULL,
            metadata_json = NULL,
            updated_at = ?
        WHERE materialized = 1
          AND (track_json IS NOT NULL OR metadata_json IS NOT NULL)
          AND NOT EXISTS (
            SELECT 1
            FROM download_jobs j
            JOIN source_tracks s
              ON s.server_base_url = j.server_base_url
             AND s.server_track_id = download_job_items.server_track_id
            WHERE j.job_id = download_job_items.job_id
          )
      ''',
        [DateTime.now().millisecondsSinceEpoch],
      );
      _pruneUnavailableLocalUserData(db);
    });
    pendingDeletes.addAll(await _host._unusedArtworkFiles(db, deleteRoots));

    if (pendingDeletes.isNotEmpty) {
      _host._transaction(db, () {
        _host._recordPendingFileDeletes(
          db,
          pendingDeletes,
          DateTime.now().millisecondsSinceEpoch,
          deleteRoots: deleteRoots,
        );
      });
    }
  }

  void _pruneUnavailableLocalUserData(Database db) {
    db.execute(
      '''
      DELETE FROM local_likes
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_likes.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
    db.execute(
      '''
      DELETE FROM local_like_states
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_like_states.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
    db.execute(
      '''
      DELETE FROM local_playlist_tracks
      WHERE NOT EXISTS (
        SELECT 1 FROM source_tracks s
        WHERE s.local_track_id = local_playlist_tracks.local_track_id
          AND s.status = ?
          AND s.file_path IS NOT NULL
      )
    ''',
      [OfflineDownloadStatus.downloaded.name],
    );
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineDeletionStoreFacade {
  _OfflineDeletionStore get _ownerDeletion;

  Future<void> resetLocalData() => _ownerDeletion.resetLocalData();

  /// Remove unfinished plans and partial files without deleting downloaded songs
  /// or their library metadata, artwork, likes, and playlist memberships.
  Future<void> clearUnfinishedDownloads() => _ownerDeletion.clearUnfinishedDownloads();

  Future<void> removeDownloads(Iterable<OfflineTrackDownload> downloads) => _ownerDeletion.removeDownloads(downloads);

  Future<OfflineDeletionResult> removeDownloadsScoped(OfflineDeletionRequest request) =>
      _ownerDeletion.removeDownloadsScoped(request);

  Future<void> _runStartupGarbageCollection(Database db) => _ownerDeletion._runStartupGarbageCollection(db);

  void _pruneUnavailableLocalUserData(Database db) => _ownerDeletion._pruneUnavailableLocalUserData(db);
}
