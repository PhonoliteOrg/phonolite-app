part of '../offline_library.dart';

class _OfflineDownloadJobStore {
  final OfflineLibraryStorage _host;

  _OfflineDownloadJobStore(this._host);

  Future<List<OfflineDownloadBatch>> readDownloadBatches() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readDownloadBatches(db);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline download batches: $err');

        return const [];
      },
    );
  }

  Future<List<OfflineDownloadJob>> readDownloadJobs() async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readDownloadJobs(db);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline download jobs: $err');

        return const [];
      },
    );
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItems(String jobId) async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readDownloadJobItems(db, jobId);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline download job items: $err');

        return const [];
      },
    );
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsLean(String jobId) async {
    if (kIsWeb) {
      return const [];
    }

    Database? db;

    try {
      developer.Timeline.startSync('offline.sqlite.readJobItemsLean');
      db = await _host._openDatabase();

      return _readDownloadJobItems(db, jobId, includeTrackJson: false);
    } catch (err) {
      AppLogger.warning('Failed to read offline download job items: $err');

      return const [];
    } finally {
      developer.Timeline.finishSync();
      _host._releaseDatabase(db);
    }
  }

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsForTracks(
    String jobId,
    Iterable<String> serverTrackIds,
  ) async {
    if (kIsWeb) {
      return const [];
    }

    final ids = serverTrackIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList(growable: false);

    if (ids.isEmpty) {
      return const [];
    }

    Database? db;

    try {
      developer.Timeline.startSync('offline.sqlite.readJobItemsWindow');
      db = await _host._openDatabase();

      return _readDownloadJobItemsForTracks(db, jobId, ids);
    } catch (err) {
      AppLogger.warning('Failed to read offline download job item window: $err');

      return const [];
    } finally {
      developer.Timeline.finishSync();
      _host._releaseDatabase(db);
    }
  }

  Future<List<OfflineDownloadJobSource>> readDownloadJobSources(String jobId) async {
    if (kIsWeb) {
      return const [];
    }

    return await _host._withDatabase(
      (db) {
        return _readDownloadJobSources(db, jobId);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to read offline download job sources: $err');

        return const [];
      },
    );
  }

  Future<void> upsertDownloadBatch(OfflineDownloadBatch batch) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _upsertDownloadBatch(db, batch);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline download batch: $err');
      },
    );
  }

  Future<void> upsertDownloadJob(OfflineDownloadJob job) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _upsertDownloadJob(db, job);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline download job: $err');
      },
    );
  }

  /// Commit the entire collection request before any of its tracks are staged.
  /// A failed commit must stop queueing, rather than leave only a partial plan.
  Future<void> saveDownloadPlan({
    required OfflineDownloadJob job,
    required OfflineDownloadBatch batch,
    List<OfflineDownloadJobItem> items = const [],
    List<OfflineDownloadJobSource> sources = const [],
  }) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          _upsertDownloadJob(db, job);

          for (final item in items) {
            _upsertDownloadJobItem(db, item);
          }

          for (final source in sources) {
            _upsertDownloadJobSource(db, source);
          }

          _upsertDownloadBatch(db, batch);
        });
      },
      onError: (error, stackTrace) {
        AppLogger.warning('Failed to persist the complete download plan: $error');
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  /// Album discovery and its track IDs must advance together across restarts.
  Future<void> saveDownloadJobDiscovery({
    required List<OfflineDownloadJobItem> items,
    required List<OfflineDownloadJobSource> sources,
  }) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final item in items) {
            _upsertDownloadJobItem(db, item);
          }

          for (final source in sources) {
            _upsertDownloadJobSource(db, source);
          }
        });
      },
      onError: (error, stackTrace) {
        AppLogger.warning('Failed to persist discovered download tracks: $error');
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> upsertDownloadJobs(List<OfflineDownloadJob> jobs) async {
    if (kIsWeb || jobs.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final job in jobs) {
            _upsertDownloadJob(db, job);
          }
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline download jobs: $err');
      },
    );
  }

  Future<void> upsertDownloadJobItems(List<OfflineDownloadJobItem> items) async {
    if (kIsWeb || items.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final item in items) {
            _upsertDownloadJobItem(db, item);
          }
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline download job items: $err');
      },
    );
  }

  Future<void> upsertDownloadJobSources(List<OfflineDownloadJobSource> sources) async {
    if (kIsWeb || sources.isEmpty) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        _host._transaction(db, () {
          for (final source in sources) {
            _upsertDownloadJobSource(db, source);
          }
        });
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to persist offline download job sources: $err');
      },
    );
  }

  Future<void> deleteDownloadBatch(String batchId) async {
    if (kIsWeb) {
      return;
    }

    return await _host._withDatabase(
      (db) {
        db.execute('DELETE FROM download_batches WHERE batch_id = ?', [batchId]);
      },
      onError: (err, stackTrace) {
        AppLogger.warning('Failed to delete offline download batch: $err');
      },
    );
  }

  Future<void> deleteDownloadJob(String jobId) async {
    if (kIsWeb) {
      return;
    }

    final trimmed = jobId.trim();

    if (trimmed.isEmpty) {
      return;
    }

    Database? db;

    try {
      final database = await _host._openDatabase();

      db = database;
      _host._transaction(database, () {
        database.execute('DELETE FROM download_job_items WHERE job_id = ?', [trimmed]);
        database.execute('DELETE FROM download_job_sources WHERE job_id = ?', [trimmed]);
        database.execute('DELETE FROM download_jobs WHERE job_id = ?', [trimmed]);
        database.execute('DELETE FROM download_batches WHERE batch_id = ?', [trimmed]);
      });
    } catch (err) {
      AppLogger.warning('Failed to delete offline download job: $err');
    } finally {
      _host._releaseDatabase(db);
    }
  }

  List<OfflineDownloadBatch> _readDownloadBatches(Database db) {
    final rows = db.select('SELECT * FROM download_batches ORDER BY updated_at DESC');

    return rows
        .map(
          (row) => OfflineDownloadBatch(
            batchId: OfflineLibraryStorage._readString(row, 'batch_id'),
            serverBaseUrl: OfflineLibraryStorage._readString(row, 'server_base_url'),
            status: OfflineLibraryStorage._parseStatus(OfflineLibraryStorage._readString(row, 'status')),
            createdAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'created_at')),
            updatedAt: OfflineLibraryStorage._dateFromMs(OfflineLibraryStorage._readInt(row, 'updated_at')),
            totalCount: OfflineLibraryStorage._readInt(row, 'total_count'),
            completedCount: OfflineLibraryStorage._readInt(row, 'completed_count'),
            failedCount: OfflineLibraryStorage._readInt(row, 'failed_count'),
            label: OfflineLibraryStorage._readNullableString(row, 'label'),
          ),
        )
        .toList(growable: false);
  }

  List<OfflineDownloadJob> _readDownloadJobs(Database db) {
    final rows = db.select('SELECT * FROM download_jobs ORDER BY updated_at DESC');

    return rows.map(_host._downloadJobFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobItem> _readDownloadJobItems(Database db, String jobId, {bool includeTrackJson = true}) {
    final rows = db.select(
      includeTrackJson
          ? 'SELECT * FROM download_job_items WHERE job_id = ? ORDER BY position'
          : '''
            SELECT
              job_id,
              position,
              server_track_id,
              status,
              materialized,
              created_at,
              updated_at,
              NULL AS track_json,
              NULL AS metadata_json,
              error
            FROM download_job_items
            WHERE job_id = ?
            ORDER BY position
          ''',
      [jobId],
    );

    return rows.map(_host._downloadJobItemFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobItem> _readDownloadJobItemsForTracks(Database db, String jobId, List<String> serverTrackIds) {
    if (serverTrackIds.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(serverTrackIds.length, '?').join(',');
    final rows = db.select(
      '''
      SELECT *
      FROM download_job_items
      WHERE job_id = ?
        AND server_track_id IN ($placeholders)
      ORDER BY position
      ''',
      <Object?>[jobId, ...serverTrackIds],
    );

    return rows.map(_host._downloadJobItemFromRow).toList(growable: false);
  }

  List<OfflineDownloadJobSource> _readDownloadJobSources(Database db, String jobId) {
    final rows = db.select('SELECT * FROM download_job_sources WHERE job_id = ? ORDER BY position', [jobId]);

    return rows.map(_host._downloadJobSourceFromRow).toList(growable: false);
  }

  void _upsertDownloadBatch(Database db, OfflineDownloadBatch batch) {
    db.execute(
      '''
      INSERT INTO download_batches (
        batch_id,
        server_base_url,
        status,
        created_at,
        updated_at,
        total_count,
        completed_count,
        failed_count,
        label
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(batch_id) DO UPDATE SET
        server_base_url = excluded.server_base_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        total_count = excluded.total_count,
        completed_count = excluded.completed_count,
        failed_count = excluded.failed_count,
        label = excluded.label
    ''',
      [
        batch.batchId,
        batch.serverBaseUrl,
        batch.status.name,
        batch.createdAt.millisecondsSinceEpoch,
        batch.updatedAt.millisecondsSinceEpoch,
        batch.totalCount,
        batch.completedCount,
        batch.failedCount,
        batch.label,
      ],
    );
  }

  void _upsertDownloadJob(Database db, OfflineDownloadJob job) {
    db.execute(
      '''
      INSERT INTO download_jobs (
        job_id,
        kind,
        server_base_url,
        status,
        created_at,
        updated_at,
        total_count,
        discovered_count,
        completed_count,
        failed_count,
        materialized_count,
        source_cursor,
        label,
        source_id,
        error,
        profile,
        server_job_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id) DO UPDATE SET
        kind = excluded.kind,
        server_base_url = excluded.server_base_url,
        status = excluded.status,
        updated_at = excluded.updated_at,
        total_count = excluded.total_count,
        discovered_count = excluded.discovered_count,
        completed_count = excluded.completed_count,
        failed_count = excluded.failed_count,
        materialized_count = excluded.materialized_count,
        source_cursor = excluded.source_cursor,
        label = excluded.label,
        source_id = excluded.source_id,
        error = excluded.error,
        profile = excluded.profile,
        server_job_id = excluded.server_job_id
    ''',
      [
        job.jobId,
        job.kind,
        job.serverBaseUrl,
        job.status.name,
        job.createdAt.millisecondsSinceEpoch,
        job.updatedAt.millisecondsSinceEpoch,
        job.totalCount,
        job.discoveredCount,
        job.completedCount,
        job.failedCount,
        job.materializedCount,
        job.sourceCursor,
        job.label,
        job.sourceId,
        job.error,
        job.profile,
        job.serverJobId,
      ],
    );
  }

  void _upsertDownloadJobItem(Database db, OfflineDownloadJobItem item) {
    final track = item.track;

    db.execute(
      '''
      INSERT INTO download_job_items (
        job_id,
        position,
        server_track_id,
        status,
        materialized,
        created_at,
        updated_at,
        track_json,
        metadata_json,
        error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id, server_track_id) DO UPDATE SET
        position = excluded.position,
        status = excluded.status,
        materialized = excluded.materialized,
        updated_at = excluded.updated_at,
        track_json = COALESCE(excluded.track_json, track_json),
        metadata_json = COALESCE(excluded.metadata_json, metadata_json),
        error = excluded.error
    ''',
      [
        item.jobId,
        item.position,
        item.serverTrackId,
        item.status.name,
        item.materialized ? 1 : 0,
        item.createdAt.millisecondsSinceEpoch,
        item.updatedAt.millisecondsSinceEpoch,
        track == null ? null : jsonEncode(track.toJson()),
        item.offlineMetadata == null ? null : jsonEncode(item.offlineMetadata!.toJson()),
        item.error,
      ],
    );
  }

  void _upsertDownloadJobSource(Database db, OfflineDownloadJobSource source) {
    db.execute(
      '''
      INSERT INTO download_job_sources (
        job_id,
        position,
        source_id,
        status,
        created_at,
        updated_at,
        label,
        error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(job_id, source_id) DO UPDATE SET
        position = excluded.position,
        status = excluded.status,
        updated_at = excluded.updated_at,
        label = excluded.label,
        error = excluded.error
    ''',
      [
        source.jobId,
        source.position,
        source.sourceId,
        source.status.name,
        source.createdAt.millisecondsSinceEpoch,
        source.updatedAt.millisecondsSinceEpoch,
        source.label,
        source.error,
      ],
    );
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _OfflineDownloadJobStoreFacade {
  _OfflineDownloadJobStore get _ownerJobs;

  Future<List<OfflineDownloadBatch>> readDownloadBatches() => _ownerJobs.readDownloadBatches();

  Future<List<OfflineDownloadJob>> readDownloadJobs() => _ownerJobs.readDownloadJobs();

  Future<List<OfflineDownloadJobItem>> readDownloadJobItems(String jobId) => _ownerJobs.readDownloadJobItems(jobId);

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsLean(String jobId) =>
      _ownerJobs.readDownloadJobItemsLean(jobId);

  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsForTracks(String jobId, Iterable<String> serverTrackIds) =>
      _ownerJobs.readDownloadJobItemsForTracks(jobId, serverTrackIds);

  Future<List<OfflineDownloadJobSource>> readDownloadJobSources(String jobId) =>
      _ownerJobs.readDownloadJobSources(jobId);

  Future<void> upsertDownloadBatch(OfflineDownloadBatch batch) => _ownerJobs.upsertDownloadBatch(batch);

  Future<void> upsertDownloadJob(OfflineDownloadJob job) => _ownerJobs.upsertDownloadJob(job);

  /// Commit the entire collection request before any of its tracks are staged.
  /// A failed commit must stop queueing, rather than leave only a partial plan.
  Future<void> saveDownloadPlan({
    required OfflineDownloadJob job,
    required OfflineDownloadBatch batch,
    List<OfflineDownloadJobItem> items = const [],
    List<OfflineDownloadJobSource> sources = const [],
  }) => _ownerJobs.saveDownloadPlan(job: job, batch: batch, items: items, sources: sources);

  /// Album discovery and its track IDs must advance together across restarts.
  Future<void> saveDownloadJobDiscovery({
    required List<OfflineDownloadJobItem> items,
    required List<OfflineDownloadJobSource> sources,
  }) => _ownerJobs.saveDownloadJobDiscovery(items: items, sources: sources);

  Future<void> upsertDownloadJobs(List<OfflineDownloadJob> jobs) => _ownerJobs.upsertDownloadJobs(jobs);

  Future<void> upsertDownloadJobItems(List<OfflineDownloadJobItem> items) => _ownerJobs.upsertDownloadJobItems(items);

  Future<void> upsertDownloadJobSources(List<OfflineDownloadJobSource> sources) =>
      _ownerJobs.upsertDownloadJobSources(sources);

  Future<void> deleteDownloadBatch(String batchId) => _ownerJobs.deleteDownloadBatch(batchId);

  Future<void> deleteDownloadJob(String jobId) => _ownerJobs.deleteDownloadJob(jobId);
}
