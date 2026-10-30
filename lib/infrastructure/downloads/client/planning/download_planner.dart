part of '../offline_download_client.dart';

class _DownloadPlanner {
  final _OfflineDownloadActorCore _host;
  int _localDataRevision = 0;

  _DownloadPlanner(this._host);

  Future<int> downloadTrack(
    Track track, {
    String? profile,
    bool playlistOwned = false,
    bool Function()? isCurrent,
  }) async {
    final requestedProfile = profile ?? _host._queueProfile;
    final dataRevision = _localDataRevision;

    await _host._ensureLoaded();

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    final baseUrl = _host.connection.baseUrl;
    final sessionRevision = _host.connection.sessionRevision;
    final serverTrackId = (track.serverTrackId ?? track.id).trim();
    final source = SourceTrackRef(serverBaseUrl: baseUrl, serverTrackId: serverTrackId);

    bool current() =>
        _host._localDataCurrent(dataRevision) &&
        _host.connection.sessionRevision == sessionRevision &&
        (isCurrent?.call() ?? true);

    if (track.serverBaseUrl != null && track.serverBaseUrl != baseUrl) {
      throw StateError('Connect to the original server to download this track.');
    }

    if (serverTrackId.isEmpty) {
      return 0;
    }

    if (!playlistOwned) {
      await _host._ownerPlaylistDownloads.registerDemand(source, ownerKind: 'manual', ownerId: source.key);
    }

    if (!current()) {
      return 0;
    }

    final existing = _host.find(baseUrl, serverTrackId);

    if (existing != null && _host._canResume(existing.status)) {
      await _host.resumeDownload(existing);

      return 0;
    }

    if (_host._downloadQueuedOrAvailable(existing)) {
      return 0;
    }

    if (requestedProfile != 'original') {
      return queueTracks([track], label: track.title, profile: requestedProfile, registerDemand: !playlistOwned);
    }

    if (_host.connection.token != null && _host.connection.token!.isNotEmpty) {
      Object? batchError;
      var batchResponded = false;

      try {
        final manifest = await _host.connection.createDownloadBatch(<String>[serverTrackId]);

        if (!current()) {
          return 0;
        }

        batchResponded = true;

        if (manifest.items.isEmpty) {
          String? reason;

          for (final item in manifest.unavailable) {
            if (item.trackId == serverTrackId) {
              reason = item.reason;
              break;
            }
          }

          throw Exception(reason ?? 'track unavailable for download');
        }

        if (playlistOwned && !await _host._storage.hasDownloadDemand(source)) {
          return 0;
        }

        if (!playlistOwned) {
          return _ownerBatch(manifest, label: track.title, isCurrent: current);
        }

        return _host._ownerPlaylistDownloads.mutate(() async {
          if (!current() || !await _host._storage.hasDownloadDemand(source)) {
            return 0;
          }

          try {
            return await _ownerBatch(manifest, label: track.title, playlistOwned: true, isCurrent: current);
          } finally {
            await _discardEmptyPlaylistBatch(manifest.batchId);
          }
        });
      } catch (err) {
        if (!current()) {
          return 0;
        }

        if (batchResponded) {
          rethrow;
        }

        batchError = err;
        AppLogger.warning('Download batch metadata failed for ${track.title}: $err');
      }

      try {
        final metadata = await _host.connection.fetchOfflineMetadata(serverTrackId);

        if (!current()) {
          return 0;
        }

        final now = DateTime.now();
        final hydratedTrack = metadata.track.copyWith(
          id: serverTrackId,
          serverBaseUrl: baseUrl,
          serverTrackId: serverTrackId,
        );
        final initial =
            existing?.copyWith(
              status: OfflineDownloadStatus.queued,
              updatedAt: now,
              filePath: null,
              error: null,
              retryCount: existing.retryCount + 1,
              track: hydratedTrack,
              offlineMetadata: metadata.copyWith(track: hydratedTrack),
            ) ??
            OfflineTrackDownload(
              serverBaseUrl: baseUrl,
              track: hydratedTrack,
              offlineMetadata: metadata.copyWith(track: hydratedTrack),
              status: OfflineDownloadStatus.queued,
              createdAt: now,
              updatedAt: now,
            );
        Future<int> stageMetadata() async {
          if (!current() || (playlistOwned && !await _host._storage.hasDownloadDemand(source))) {
            return 0;
          }

          final queued = await _host._storageOperation(() => _host._storage.prepareDownload(initial));

          if (!current()) {
            return 0;
          }

          _host._clearObsoleteStopMarkersForQueue(queued);

          await _host._replace(queued, persist: true);

          if (!current()) {
            return 0;
          }

          _host._schedule();

          return 1;
        }

        return playlistOwned ? _host._ownerPlaylistDownloads.mutate(stageMetadata) : stageMetadata();
      } catch (err) {
        if (!_host._localDataCurrent(dataRevision)) {
          return 0;
        }

        throw Exception('offline metadata unavailable for ${track.title}: $err; batch error: $batchError');
      }
    }

    throw Exception('server session required to fetch offline metadata for ${track.title}');
  }

  Future<int> queueTracks(
    Iterable<Track> tracks, {
    String? label,
    String kind = 'tracks',
    String? sourceId,
    String? profile,
    bool registerDemand = true,
  }) async {
    final requestedProfile = profile ?? _host._queueProfile;
    final dataRevision = _localDataRevision;

    await _host._ensureLoaded();

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    final baseUrl = _host.connection.baseUrl;
    final sessionRevision = _host.connection.sessionRevision;

    bool sessionCurrent() =>
        _host.connection.baseUrl == baseUrl &&
        _host.connection.sessionRevision == sessionRevision &&
        _host._localDataCurrent(dataRevision);

    final now = DateTime.now();
    final seen = <String>{};
    final trackList = <Track>[];

    for (final track in tracks) {
      final id = track.id.trim();

      if (id.isEmpty || !seen.add(id)) {
        continue;
      }

      if (track.serverBaseUrl != null && track.serverBaseUrl != baseUrl) {
        throw StateError('The download source does not belong to the connected server.');
      }

      if (registerDemand) {
        await _host._ownerPlaylistDownloads.registerDemand(
          SourceTrackRef(serverBaseUrl: baseUrl, serverTrackId: id),
          ownerKind: 'collection',
          ownerId: '$kind:${sourceId ?? label ?? 'tracks'}',
        );
      }

      if (!sessionCurrent()) {
        return 0;
      }

      trackList.add(track.copyWith(id: id, serverBaseUrl: baseUrl, serverTrackId: id));
    }

    if (trackList.isEmpty) {
      return 0;
    }

    final pending = <Track>[];

    for (var index = 0; index < trackList.length; index += 1) {
      final track = trackList[index];
      final existing = _host.find(baseUrl, track.id);

      if (_host._downloadQueuedOrAvailable(existing)) {
        continue;
      }

      pending.add(track);
    }

    if (pending.isEmpty) {
      return 0;
    }

    final jobId = _host._stableJobId(
      kind,
      _host._rollingJobSignature(label: label, trackIds: pending.map((track) => track.id), profile: requestedProfile),
    );
    if (requestedProfile != 'original') {
      final existingJob = await _host._reuseOrClearRollingJob(
        jobId: jobId,
        kind: kind,
        serverBaseUrl: baseUrl,
        label: label,
        trackIds: pending.map((track) => track.id),
        profile: requestedProfile,
      );
      if (existingJob != null) {
        _host._scheduleTopUp();
        return 0;
      }
      final attemptId = _host._queueAttemptRequestId(jobId);
      final job = OfflineDownloadJob(
        profile: requestedProfile,
        jobId: attemptId,
        kind: kind,
        serverBaseUrl: baseUrl,
        status: OfflineDownloadStatus.queued,
        createdAt: now,
        updatedAt: now,
        totalCount: pending.length,
        discoveredCount: pending.length,
        label: label,
        sourceId: sourceId,
      );
      final items = [
        for (var index = 0; index < pending.length; index++)
          OfflineDownloadJobItem(
            jobId: attemptId,
            position: index,
            serverTrackId: pending[index].id,
            status: OfflineDownloadStatus.queued,
            materialized: false,
            createdAt: now,
            updatedAt: now,
            track: pending[index],
          ),
      ];
      await _host._insertRollingJob(job, items: items);
      _host._scheduleTopUp();
      return pending.length;
    }

    final v2Queued = await _host._tryQueueV2DownloadJob(
      scope: DownloadJobScopeV2(
        kind: pending.length == 1 ? 'track' : 'track_set',
        id: pending.length == 1 ? pending.first.id : null,
        trackIds: pending.length == 1 ? const <String>[] : pending.map((track) => track.id).toList(growable: false),
      ),
      clientRequestId: jobId,
      kind: kind,
      label: label,
      sourceId: sourceId,
    );

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    if (v2Queued != null) {
      return v2Queued;
    }

    final existingJob = await _host._reuseOrClearRollingJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      label: label,
      trackIds: pending.map((track) => track.id),
    );

    if (existingJob != null) {
      _host._scheduleTopUp();

      return 0;
    }

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: kind,
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
      totalCount: pending.length,
      discoveredCount: pending.length,
      label: label,
      sourceId: sourceId,
    );
    final items = <OfflineDownloadJobItem>[
      for (var index = 0; index < pending.length; index += 1)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: index,
          serverTrackId: pending[index].id,
          status: OfflineDownloadStatus.queued,
          materialized: false,
          createdAt: now,
          updatedAt: now,
          track: pending[index],
        ),
    ];

    await _host._insertRollingJob(job, items: items);
    await _host._topUpRollingJob(job);

    _host._scheduleQueuedDownloads();

    return pending.length;
  }

  Future<int> queueBatch(DownloadBatchManifest manifest, {String? label}) => _ownerBatch(manifest, label: label);

  Future<void> _discardEmptyPlaylistBatch(String batchId) async {
    if (_host._disposed ||
        _host._resettingLocalData ||
        _host._downloads.any((download) => download.batchId == batchId) ||
        _host._isRollingJob(batchId)) {
      return;
    }

    await _host._storage.deleteDownloadBatch(batchId);
    _host._batches = _host._batches.where((batch) => batch.batchId != batchId).toList(growable: false);
    _host._emitBatches();
  }

  Future<int> _ownerBatch(
    DownloadBatchManifest manifest, {
    String? label,
    bool playlistOwned = false,
    bool Function()? isCurrent,
  }) async {
    final dataRevision = _localDataRevision;

    await _host._ensureLoaded();

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    if (manifest.items.isEmpty) {
      return 0;
    }

    if (!(isCurrent?.call() ?? true)) {
      return 0;
    }

    if (!playlistOwned) {
      for (final item in manifest.items) {
        await _host._ownerPlaylistDownloads.registerDemand(
          SourceTrackRef(serverBaseUrl: _host.connection.baseUrl, serverTrackId: item.trackId),
          ownerKind: 'manual',
          ownerId: 'batch:${manifest.batchId}',
        );
      }
    }

    if (manifest.items.length > _OfflineDownloadActorCore._rollingWindowSize) {
      return _host._queueRollingBatch(manifest, label: label);
    }

    final baseUrl = _host.connection.baseUrl;
    final now = DateTime.now();
    final batch = OfflineDownloadBatch(
      batchId: manifest.batchId,
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: manifest.createdAt,
      updatedAt: now,
      totalCount: manifest.items.length,
      label: label,
    );

    await _host._upsertBatch(batch);

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    final pending = <OfflineTrackDownload>[];

    for (var index = 0; index < manifest.items.length; index += 1) {
      final item = manifest.items[index];
      final source = SourceTrackRef(serverBaseUrl: baseUrl, serverTrackId: item.trackId);

      if (!(isCurrent?.call() ?? true) || (playlistOwned && !await _host._storage.hasDownloadDemand(source))) {
        return 0;
      }
      final track = item.offlineMetadata.track.copyWith(
        id: item.trackId,
        serverBaseUrl: baseUrl,
        serverTrackId: item.trackId,
      );
      final offlineMetadata = item.offlineMetadata.copyWith(track: track);
      final existing = _host.find(baseUrl, item.trackId);

      if (_host._downloadQueuedOrAvailable(existing)) {
        continue;
      }

      final download =
          existing?.copyWith(
            batchId: manifest.batchId,
            downloadUrl: item.downloadUrl,
            status: OfflineDownloadStatus.queued,
            updatedAt: now,
            filePath: null,
            bytesTotal: item.byteLength > 0 ? item.byteLength : null,
            etag: item.etag.isEmpty ? null : item.etag,
            expectedSha256: item.sha256.isEmpty ? null : item.sha256,
            contentType: item.contentType,
            error: null,
            retryCount: existing.retryCount + 1,
            priority: manifest.items.length - index,
            track: track,
            offlineMetadata: offlineMetadata,
          ) ??
          OfflineTrackDownload(
            serverBaseUrl: baseUrl,
            batchId: manifest.batchId,
            downloadUrl: item.downloadUrl,
            track: track,
            offlineMetadata: offlineMetadata,
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            bytesTotal: item.byteLength > 0 ? item.byteLength : null,
            etag: item.etag.isEmpty ? null : item.etag,
            expectedSha256: item.sha256.isEmpty ? null : item.sha256,
            contentType: item.contentType,
            priority: manifest.items.length - index,
          );

      pending.add(download);
    }

    var queuedCount = 0;

    if (pending.isNotEmpty) {
      for (final chunk in _host._chunks(pending, _OfflineDownloadActorCore._queuePersistChunkSize)) {
        if (!_host._localDataCurrent(dataRevision)) {
          return 0;
        }

        final prepared = await _host._storageOperation(() => _host._storage.prepareDownloads(chunk));

        if (!(isCurrent?.call() ?? true)) {
          return 0;
        }

        if (!_host._localDataCurrent(dataRevision)) {
          return 0;
        }

        _host._replaceManyInMemory(prepared);

        await _host._storageOperation(() => _host._storage.upsertDownloads(prepared));

        if (!_host._localDataCurrent(dataRevision)) {
          return 0;
        }

        queuedCount += prepared.length;
        await Future<void>.delayed(_OfflineDownloadActorCore._queuePersistYieldDelay);
      }

      await _host._refreshBatchCounts(manifest.batchId);

      _host._schedule();
    } else {
      await _host._refreshBatchCounts(manifest.batchId);
    }

    return queuedCount;
  }

  Future<int> queueArtist(Artist artist, List<Album> albums) async {
    final requestedProfile = _host._queueProfile;
    final dataRevision = _localDataRevision;

    await _host._ensureLoaded();

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    final sources = albums.where((album) => album.id.trim().isNotEmpty).toList(growable: false);

    if (sources.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final baseUrl = _host.connection.baseUrl;
    final collectionId = _host._stableJobId(
      'artist',
      _host._rollingJobSignature(
        label: artist.name,
        sourceIds: sources.map((album) => album.id),
        profile: requestedProfile,
      ),
    );
    final existingJob = await _host._reuseOrClearRollingJob(
      jobId: collectionId,
      kind: 'artist',
      serverBaseUrl: baseUrl,
      label: artist.name,
      sourceIds: sources.map((album) => album.id),
    );

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    if (existingJob != null) {
      _host._scheduleTopUp();

      return 0;
    }

    // A new intent must not share an ID with a deleted plan: its delayed
    // discovery or server response may still be in flight.
    final jobId = _host._queueAttemptRequestId(collectionId);
    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: 'artist',
      profile: requestedProfile,
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
      totalCount: sources.fold<int>(0, (sum, album) => sum + album.trackCount),
      label: artist.name,
      sourceId: artist.id,
    );
    final jobSources = <OfflineDownloadJobSource>[
      for (var index = 0; index < sources.length; index += 1)
        OfflineDownloadJobSource(
          jobId: job.jobId,
          position: index,
          sourceId: sources[index].id,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          label: sources[index].title,
        ),
    ];

    await _host._insertRollingJob(job.copyWith(status: OfflineDownloadStatus.preparing), sources: jobSources);

    if (!_host._localDataCurrent(dataRevision)) {
      return 0;
    }

    if (requestedProfile != 'original') {
      await _host._storage.upsertDownloadJob(job);
      _host._jobs = [for (final existing in _host._jobs) existing.jobId == job.jobId ? job : existing];
      _host._emitJobs();
      _host._scheduleTopUp();
      return job.totalCount > 0 ? job.totalCount : sources.length;
    }

    // Persist the artist and every requested album before a network call can
    // be interrupted. The server manifest enriches this durable local intent.
    final v2Queued = await _host._tryQueueV2DownloadJob(
      scope: DownloadJobScopeV2(kind: 'artist', id: artist.id),
      clientRequestId: jobId,
      kind: 'artist',
      label: artist.name,
      sourceId: artist.id,
      artistAlbums: sources,
      localIntentJobId: jobId,
    );

    if (!_host._localDataCurrent(dataRevision) || _host._jobById(jobId) == null) {
      return 0;
    }

    if (v2Queued != null && v2Queued > 0) {
      // The replacement plan has already committed, including all albums.
      await _host._deleteRollingJob(jobId);
      _host._scheduleTopUp();

      return v2Queued;
    }

    _host._jobs = _host._jobs.map((item) => item.jobId == jobId ? job : item).toList(growable: false);
    await _host._storage.upsertDownloadJob(job);

    _host._emitJobs();

    _host._scheduleTopUp();

    return job.totalCount > 0 ? job.totalCount : sources.length;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadPlannerFacade {
  _DownloadPlanner get _ownerPlanning;

  int get _localDataRevision => _ownerPlanning._localDataRevision;

  set _localDataRevision(int value) => _ownerPlanning._localDataRevision = value;

  Future<int> downloadTrack(Track track) => _ownerPlanning.downloadTrack(track);

  Future<int> queueTracks(Iterable<Track> tracks, {String? label, String kind = 'tracks', String? sourceId}) =>
      _ownerPlanning.queueTracks(tracks, label: label, kind: kind, sourceId: sourceId);

  Future<int> queueBatch(DownloadBatchManifest manifest, {String? label}) =>
      _ownerPlanning.queueBatch(manifest, label: label);

  Future<int> queueArtist(Artist artist, List<Album> albums) => _ownerPlanning.queueArtist(artist, albums);
}
