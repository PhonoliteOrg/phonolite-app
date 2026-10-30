part of '../offline_download_client.dart';

/// Prepares durable compressed jobs without entering the Original fallback path.
class _CompressedDownloadJobs {
  final _OfflineDownloadActorCore _host;
  Timer? _pollTimer;

  _CompressedDownloadJobs(this._host);

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollLater() {
    if (_host._disposed || _host._resettingLocalData || _pollTimer != null) {
      return;
    }

    _pollTimer = Timer(const Duration(seconds: 1), () {
      _pollTimer = null;
      _host._scheduleTopUp();
    });
  }

  bool _sourceBusy(OfflineTrackDownload existing, String jobId) {
    return _host._active.containsKey(_host._downloadKey(existing)) ||
        _host._downloadQueuedOrAvailable(existing) ||
        (existing.batchId != jobId && existing.status == OfflineDownloadStatus.paused);
  }

  Future<void> applyAction(OfflineDownloadJob job, String action) async {
    if (job.serverJobId == null ||
        _host.connection.baseUrl != job.serverBaseUrl ||
        _host.connection.token?.isNotEmpty != true) {
      return;
    }
    try {
      await _host.connection.applyDownloadJobAction(jobId: job.serverJobId!, action: action);
    } catch (error) {
      AppLogger.warning('Could not $action compressed server download: $error');
    }
  }

  Future<void> topUp(OfflineDownloadJob job) async {
    final revision = _host._localDataRevision;
    final session = _host.connection.sessionRevision;

    bool current() =>
        _host._jobById(job.jobId) != null &&
        _host._localDataCurrent(revision) &&
        _host.connection.sessionRevision == session &&
        _host.connection.baseUrl == job.serverBaseUrl &&
        _host.connection.token?.isNotEmpty == true &&
        !_host._pausedServerUrls.contains(job.serverBaseUrl) &&
        _host._jobById(job.jobId)?.status != OfflineDownloadStatus.paused &&
        _host._jobById(job.jobId)?.status != OfflineDownloadStatus.canceled;

    if (!current()) {
      return;
    }

    try {
      final capabilities = await _host.connection.fetchCapabilities();

      if (!current()) {
        return;
      }

      if (!capabilities.downloadJobsV2 || !capabilities.downloadProfiles.contains(job.profile)) {
        throw StateError(
          'This server does not support the selected download quality. Choose Original or update the server.',
        );
      }

      final localItems = _host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[];
      final clientId = await _host._storage.readOrCreateClientId();
      final DownloadJobV2 remote;

      if (job.serverJobId == null) {
        final ids = localItems.map((item) => item.serverTrackId).toList(growable: false);
        final scope = job.kind == 'artist' && job.sourceId != null
            ? DownloadJobScopeV2(kind: 'artist', id: job.sourceId)
            : DownloadJobScopeV2(
                kind: ids.length == 1 ? 'track' : 'track_set',
                id: ids.length == 1 ? ids.first : null,
                trackIds: ids.length == 1 ? const [] : ids,
              );
        remote = await _host.connection.createDownloadJob(
          clientId: clientId,
          clientRequestId: job.jobId,
          scope: scope,
          profile: job.profile,
        );
      } else {
        remote = await _host.connection.fetchDownloadJob(job.serverJobId!);
      }

      if (!current()) {
        final latest = _host._jobById(job.jobId);
        if (!_host._disposed &&
            _host.connection.sessionRevision == session &&
            _host.connection.baseUrl == job.serverBaseUrl &&
            _host.connection.token?.isNotEmpty == true &&
            remote.profile == job.profile &&
            remote.clientId == clientId) {
          try {
            if (latest?.status == OfflineDownloadStatus.paused) {
              final paused = latest!.copyWith(serverJobId: remote.jobId);
              await _host._storage.upsertDownloadJob(paused);
              _host._jobs = [for (final existing in _host._jobs) existing.jobId == paused.jobId ? paused : existing];
              _host._emitJobs();
            }
            await _host.connection.applyDownloadJobAction(
              jobId: remote.jobId,
              action: latest?.status == OfflineDownloadStatus.paused ? 'pause' : 'cancel',
            );
          } catch (error) {
            AppLogger.warning('Could not stop late server preparation: $error');
          }
        }
        return;
      }

      if (remote.profile != job.profile || remote.clientId != clientId || remote.jobId.isEmpty) {
        throw StateError('Server returned a different download profile or client. No audio was downloaded.');
      }

      if (remote.status == 'paused') {
        final paused = (_host._jobById(job.jobId) ?? job).copyWith(
          serverJobId: remote.jobId,
          status: OfflineDownloadStatus.paused,
          updatedAt: DateTime.now(),
        );
        await _host._storage.upsertDownloadJob(paused);
        _host._jobs = [for (final existing in _host._jobs) existing.jobId == paused.jobId ? paused : existing];
        _host._emitJobs();
        return;
      }

      job = (_host._jobById(job.jobId) ?? job).copyWith(
        serverJobId: remote.jobId,
        totalCount: remote.totalCount,
        discoveredCount: remote.items.length,
        status: OfflineDownloadStatus.queued,
        updatedAt: DateTime.now(),
        error: null,
      );
      await _host._storage.upsertDownloadJob(job);
      if (!current()) {
        return;
      }
      _host._jobs = [for (final existing in _host._jobs) existing.jobId == job.jobId ? job : existing];

      final sources = _host._jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[];
      final discoveredSources = [
        for (final source in sources)
          source.copyWith(status: OfflineDownloadStatus.downloaded, updatedAt: DateTime.now(), error: null),
      ];
      if (discoveredSources.isNotEmpty) {
        await _host._storage.upsertDownloadJobSources(discoveredSources);
        _host._jobSourcesByJobId[job.jobId] = discoveredSources;
      }

      final previous = {for (final item in localItems) item.serverTrackId: item};
      final items = <OfflineDownloadJobItem>[];
      final ready = <DownloadJobItemV2>[];
      var waiting = false;
      final now = DateTime.now();

      for (final item in remote.items) {
        final old = previous[item.trackId];
        final existing = _host.find(job.serverBaseUrl, item.trackId);
        final available = existing != null && _host._downloadAvailable(existing);
        final materialized =
            available || (existing?.batchId == job.jobId && _host._downloadQueuedOrAvailable(existing));
        final stopped = old?.status == OfflineDownloadStatus.canceled || item.status == 'canceled';
        final failed = item.status == 'failed' || item.status == 'metadata_failed';
        final OfflineDownloadStatus status;
        if (stopped) {
          status = OfflineDownloadStatus.canceled;
        } else if (available) {
          status = OfflineDownloadStatus.downloaded;
        } else if (failed) {
          status = OfflineDownloadStatus.failed;
        } else if (materialized) {
          status = existing!.status;
        } else {
          status = OfflineDownloadStatus.queued;
        }
        items.add(
          OfflineDownloadJobItem(
            jobId: job.jobId,
            position: item.position,
            serverTrackId: item.trackId,
            status: status,
            materialized: materialized,
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
            track: item.offlineMetadata?.track ?? old?.track,
            offlineMetadata: item.offlineMetadata ?? old?.offlineMetadata,
            error: failed ? item.error : old?.error,
          ),
        );

        if (!materialized && !stopped && !failed) {
          if (existing != null && _sourceBusy(existing, job.jobId)) {
            waiting = true;
          } else if (item.readyToDownload || item.status == 'complete') {
            ready.add(item);
          } else {
            waiting = true;
          }
        }
      }

      await _host._storage.upsertDownloadJobItems(items);
      if (!current()) {
        return;
      }
      _host._jobItemsByJobId[job.jobId] = items;
      final occupying = _host._downloads
          .where((item) => item.batchId == job.jobId && _host._ownerRolling._windowOccupyingStatus(item.status))
          .length;
      final slots = _OfflineDownloadActorCore._rollingWindowSize - occupying;
      final downloads = <OfflineTrackDownload>[];

      for (final item in ready.take(slots > 0 ? slots : 0)) {
        if (item.profile != job.profile ||
            item.renditionId == null ||
            item.downloadUrl == null ||
            item.byteLength == null ||
            item.byteLength! <= 0 ||
            item.sha256?.length != 64 ||
            item.etag == null ||
            item.offlineMetadata == null) {
          throw StateError('Server returned an incomplete compressed file contract. No Original fallback was used.');
        }
        final source = SourceTrackRef(serverBaseUrl: job.serverBaseUrl, serverTrackId: item.trackId);
        if (job.kind == 'artist') {
          await _host._ownerPlaylistDownloads.registerDemand(source, ownerKind: 'collection', ownerId: job.jobId);
        }
        if (!await _host._storage.hasDownloadDemand(source)) {
          final index = items.indexWhere((value) => value.serverTrackId == item.trackId);
          items[index] = items[index].copyWith(status: OfflineDownloadStatus.canceled, materialized: true);
          continue;
        }
        final latest = _host.find(job.serverBaseUrl, item.trackId);
        if (latest != null && (_host._downloadAvailable(latest) || _sourceBusy(latest, job.jobId))) {
          waiting = true;
          continue;
        }
        final track = item.offlineMetadata!.track.copyWith(
          id: item.trackId,
          serverBaseUrl: job.serverBaseUrl,
          serverTrackId: item.trackId,
        );
        downloads.add(
          OfflineTrackDownload(
            profile: job.profile,
            renditionId: item.renditionId,
            serverBaseUrl: job.serverBaseUrl,
            batchId: job.jobId,
            downloadUrl: item.downloadUrl,
            track: track,
            offlineMetadata: item.offlineMetadata!.copyWith(track: track),
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            bytesTotal: item.byteLength,
            etag: item.etag,
            expectedSha256: item.sha256,
            contentType: item.contentType,
            priority: remote.items.length - item.position,
          ),
        );
      }

      if (!current()) {
        return;
      }
      await _host._storage.upsertDownloadJobItems(items);
      _host._jobItemsByJobId[job.jobId] = items;
      if (downloads.isNotEmpty) {
        await _host._persistMaterializedDownloads(job.jobId, downloads);
      }
      await _host._refreshJobCounts(job.jobId);
      _host._scheduleQueuedDownloads();

      final pending = (_host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).any(
        (item) => !item.materialized && item.status == OfflineDownloadStatus.queued,
      );
      if (waiting || pending) {
        _pollLater();
      }
    } catch (error) {
      if (!current()) {
        return;
      }
      final failed = (_host._jobById(job.jobId) ?? job).copyWith(
        status: OfflineDownloadStatus.failed,
        updatedAt: DateTime.now(),
        error: error is StateError ? error.message : error.toString(),
      );
      await _host._storage.upsertDownloadJob(failed);
      _host._jobs = [for (final existing in _host._jobs) existing.jobId == job.jobId ? failed : existing];
      await _host._upsertBatch(
        OfflineDownloadBatch(
          batchId: failed.jobId,
          serverBaseUrl: failed.serverBaseUrl,
          status: failed.status,
          createdAt: failed.createdAt,
          updatedAt: failed.updatedAt,
          totalCount: failed.totalCount,
          failedCount: failed.totalCount,
          label: failed.label,
        ),
      );
      _host._emitJobs();
      AppLogger.warning('Compressed download preparation failed: $error');
    }
  }
}
