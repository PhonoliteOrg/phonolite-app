part of '../offline_download_client.dart';

class _RollingDownloadJobs {
  final _OfflineDownloadActorCore _host;
  List<OfflineDownloadJob> _jobs = <OfflineDownloadJob>[];
  final Map<String, List<OfflineDownloadJobItem>> _jobItemsByJobId = <String, List<OfflineDownloadJobItem>>{};
  final Map<String, List<OfflineDownloadJobSource>> _jobSourcesByJobId = <String, List<OfflineDownloadJobSource>>{};
  bool _topUpRunning = false;
  int _queueAttemptSequence = 0;

  _RollingDownloadJobs(this._host);

  Future<int> _queueRollingBatch(DownloadBatchManifest manifest, {String? label}) async {
    final baseUrl = _host.connection.baseUrl;
    final now = DateTime.now();
    final jobId = manifest.batchId.trim().isEmpty
        ? _stableJobId(
            'batch',
            _rollingJobSignature(label: label, trackIds: manifest.items.map((item) => item.trackId)),
          )
        : manifest.batchId.trim();
    final existingJob = await _reuseOrClearRollingJob(
      jobId: jobId,
      kind: 'batch',
      serverBaseUrl: baseUrl,
      label: label,
      trackIds: manifest.items.map((item) => item.trackId),
    );

    if (existingJob != null) {
      _host._scheduleTopUp();

      return 0;
    }

    final job = OfflineDownloadJob(
      jobId: jobId,
      kind: 'batch',
      serverBaseUrl: baseUrl,
      status: OfflineDownloadStatus.queued,
      createdAt: manifest.createdAt,
      updatedAt: now,
      totalCount: manifest.items.length,
      discoveredCount: manifest.items.length,
      label: label,
    );
    final items = <OfflineDownloadJobItem>[
      for (var index = 0; index < manifest.items.length; index += 1)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: index,
          serverTrackId: manifest.items[index].trackId,
          status: OfflineDownloadStatus.queued,
          materialized: false,
          createdAt: now,
          updatedAt: now,
          track: manifest.items[index].offlineMetadata.track.copyWith(
            id: manifest.items[index].trackId,
            serverBaseUrl: baseUrl,
            serverTrackId: manifest.items[index].trackId,
          ),
          offlineMetadata: manifest.items[index].offlineMetadata.copyWith(
            track: manifest.items[index].offlineMetadata.track.copyWith(
              id: manifest.items[index].trackId,
              serverBaseUrl: baseUrl,
              serverTrackId: manifest.items[index].trackId,
            ),
          ),
        ),
    ];

    await _insertRollingJob(job, items: items);
    await _host._materializeManifestItems(
      job,
      manifest.items.take(_OfflineDownloadActorCore._rollingWindowSize).toList(growable: false),
    );

    _host._scheduleQueuedDownloads();

    return manifest.items.length;
  }

  Future<void> _insertRollingJob(
    OfflineDownloadJob job, {
    List<OfflineDownloadJobItem> items = const <OfflineDownloadJobItem>[],
    List<OfflineDownloadJobSource> sources = const <OfflineDownloadJobSource>[],
  }) async {
    final dataRevision = _host._localDataRevision;

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    final batch = OfflineDownloadBatch(
      batchId: job.jobId,
      serverBaseUrl: job.serverBaseUrl,
      status: job.status,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      totalCount: job.totalCount > 0 ? job.totalCount : job.discoveredCount,
      completedCount: job.completedCount,
      failedCount: job.failedCount,
      label: job.label,
    );

    await _host._storageOperation(
      () => _host._storage.saveDownloadPlan(job: job, items: items, sources: sources, batch: batch),
    );

    if (!_host._localDataCurrent(dataRevision)) {
      return;
    }

    _jobs = [job, ..._jobs.where((item) => item.jobId != job.jobId)];
    _jobItemsByJobId[job.jobId] = items;
    _jobSourcesByJobId[job.jobId] = sources;
    _host._batches = [batch, ..._host._batches.where((item) => item.batchId != job.jobId)];
    _host._emitBatches();
    _host._emitJobs();
  }

  Future<OfflineDownloadJob?> _reuseOrClearRollingJob({
    String? profile,
    required String jobId,
    required String kind,
    required String serverBaseUrl,
    required String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) async {
    final duplicates = _jobs
        .where(
          (job) =>
              job.jobId == jobId ||
              _jobMatchesRollingCollection(
                job,
                profile: profile,
                kind: kind,
                serverBaseUrl: serverBaseUrl,
                label: label,
                trackIds: trackIds,
                sourceIds: sourceIds,
              ),
        )
        .toList(growable: false);

    if (duplicates.isEmpty) {
      return null;
    }

    final blocking = duplicates.where(_jobBlocksNewQueue).toList(growable: false);

    if (blocking.isNotEmpty) {
      final keep = _chooseRollingJobToKeep(blocking);

      for (final duplicate in duplicates) {
        if (duplicate.jobId != keep.jobId) {
          await _deleteRollingJob(duplicate.jobId, removePendingDownloads: true);
        }
      }

      return keep;
    }

    for (final duplicate in duplicates) {
      await _deleteRollingJob(duplicate.jobId, removePendingDownloads: true);
    }

    return null;
  }

  Future<void> _reconcileLoadedRollingJobs() async {
    for (final job in List<OfflineDownloadJob>.from(_jobs)) {
      final items = List<OfflineDownloadJobItem>.from(_jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]);

      if (items.isEmpty) {
        await _refreshJobCounts(job.jobId);
        continue;
      }

      final changed = <OfflineDownloadJobItem>[];

      for (var index = 0; index < items.length; index += 1) {
        final item = items[index];

        if (item.status == OfflineDownloadStatus.canceled) {
          continue;
        }

        final download = _host.find(job.serverBaseUrl, item.serverTrackId);

        if (!item.materialized && download == null) {
          continue;
        }

        OfflineDownloadJobItem? updated;

        if (download == null) {
          updated = item.copyWith(
            status: OfflineDownloadStatus.queued,
            materialized: false,
            updatedAt: DateTime.now(),
            error: null,
          );
        } else if (download.batchId != job.jobId) {
          final sharingPendingSource =
              job.profile != 'original' &&
              !_host._downloadAvailable(download) &&
              (_host._downloadQueuedOrAvailable(download) || download.status == OfflineDownloadStatus.paused);
          final OfflineDownloadStatus sharedStatus;
          if (_host._downloadAvailable(download)) {
            sharedStatus = OfflineDownloadStatus.downloaded;
          } else if (sharingPendingSource) {
            sharedStatus = OfflineDownloadStatus.queued;
          } else {
            sharedStatus = OfflineDownloadStatus.canceled;
          }
          updated = item.copyWith(
            status: sharedStatus,
            materialized: !sharingPendingSource,
            updatedAt: DateTime.now(),
            track: download.track,
            error: _host._downloadAvailable(download) ? null : 'download owned by another job',
          );
        } else if (!item.materialized || download.status != item.status || item.track == null) {
          updated = item.copyWith(
            status: download.status,
            materialized: true,
            updatedAt: download.updatedAt,
            track: download.track,
            error: download.error,
          );
        }

        if (updated == null) {
          continue;
        }

        items[index] = updated;
        changed.add(updated);
      }

      if (changed.isNotEmpty) {
        _jobItemsByJobId[job.jobId] = items;
        await _host._storage.upsertDownloadJobItems(changed);
      }

      await _refreshJobCounts(job.jobId);
      await _deleteRollingJobIfAbandoned(job.jobId);
    }
  }

  Future<void> _pruneDuplicateRollingJobs() async {
    final groups = <String, List<OfflineDownloadJob>>{};

    for (final job in _jobs) {
      final key = _rollingJobCollectionKey(job);
      if (key == null) {
        continue;
      }

      groups.putIfAbsent(key, () => <OfflineDownloadJob>[]).add(job);
    }

    for (final group in groups.values) {
      if (group.length < 2) {
        continue;
      }

      final keep = _chooseRollingJobToKeep(group);

      for (final job in group) {
        if (job.jobId == keep.jobId) {
          continue;
        }

        await _deleteRollingJob(job.jobId, removePendingDownloads: true);
      }
    }
  }

  Future<void> _deleteRollingJob(String jobId, {bool removePendingDownloads = false}) async {
    final trimmed = jobId.trim();

    if (trimmed.isEmpty) {
      return;
    }

    final removableDownloads = removePendingDownloads
        ? _host._downloads
              .where((download) => download.batchId == trimmed && download.status != OfflineDownloadStatus.downloaded)
              .toList(growable: false)
        : const <OfflineTrackDownload>[];

    final previous = _jobById(trimmed);
    _forgetRollingJob(trimmed);

    if (removePendingDownloads && previous?.profile != 'original' && previous != null) {
      await _host._compressedJobs.applyAction(previous, 'cancel');
    }
    await _host._storage.deleteDownloadJob(trimmed);

    if (removePendingDownloads && removableDownloads.isNotEmpty) {
      await _host.removeDownloads(removableDownloads);
    }
  }

  void _forgetRollingJob(String jobId) {
    final trimmed = jobId.trim();
    final hadJob = _jobs.any((job) => job.jobId == trimmed);
    final hadBatch = _host._batches.any((batch) => batch.batchId == trimmed);

    _jobs = _jobs.where((job) => job.jobId != trimmed).toList(growable: false);
    _host._batches = _host._batches.where((batch) => batch.batchId != trimmed).toList(growable: false);
    _jobItemsByJobId.remove(trimmed);
    _jobSourcesByJobId.remove(trimmed);

    if (hadJob) {
      _host._emitJobs();
    }

    if (hadBatch) {
      _host._emitBatches();
    }
  }

  Future<bool> _deleteRollingJobIfAbandoned(String jobId) async {
    final job = _jobById(jobId);
    if (job == null) {
      return false;
    }

    final hasDownloads = _host._downloads.any((download) => download.batchId == jobId);

    if (hasDownloads) {
      return false;
    }

    final items = _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[];

    if (items.isEmpty) {
      return false;
    }

    final sources = _jobSourcesByJobId[jobId] ?? const <OfflineDownloadJobSource>[];
    final hasPendingSource = sources.any(
      (source) =>
          source.status == OfflineDownloadStatus.queued ||
          source.status == OfflineDownloadStatus.downloading ||
          source.status == OfflineDownloadStatus.preparing ||
          source.status == OfflineDownloadStatus.validating ||
          source.status == OfflineDownloadStatus.paused ||
          source.status == OfflineDownloadStatus.failed,
    );

    if (hasPendingSource) {
      return false;
    }

    final onlyRemovedOrCompleted = items.every(
      (item) => item.status == OfflineDownloadStatus.canceled || item.status == OfflineDownloadStatus.downloaded,
    );

    if (!onlyRemovedOrCompleted) {
      return false;
    }

    await _deleteRollingJob(jobId);

    return true;
  }

  Future<void> _topUpRollingJobsForCurrentServer() async {
    if (_topUpRunning || !_host._loaded || _host._disposed) {
      return;
    }

    _topUpRunning = true;

    try {
      final baseUrl = _host.connection.baseUrl;

      if (_host._pausedServerUrls.contains(baseUrl)) {
        return;
      }

      final runnable = _jobs
          .where(
            (job) =>
                job.serverBaseUrl == baseUrl &&
                (job.status == OfflineDownloadStatus.queued || job.status == OfflineDownloadStatus.downloading),
          )
          .toList(growable: false);

      for (final job in runnable) {
        try {
          await _topUpRollingJob(job);
        } catch (error) {
          // Keep the durable request queued so a later reconnect can retry it.
          AppLogger.warning('Could not continue download ${job.label ?? job.jobId}: $error');
        }
      }
    } finally {
      _topUpRunning = false;
    }

    _host._scheduleQueuedDownloads();
  }

  Future<void> _topUpRollingJob(OfflineDownloadJob job) async {
    developer.Timeline.startSync('offline.job.topUp');

    try {
      final latestJob = _jobById(job.jobId);

      if (latestJob == null ||
          latestJob.status == OfflineDownloadStatus.paused ||
          latestJob.status == OfflineDownloadStatus.canceled ||
          _host._pausedServerUrls.contains(latestJob.serverBaseUrl)) {
        return;
      }

      job = latestJob;

      if (job.profile != 'original') {
        await _host._compressedJobs.topUp(job);
        return;
      }

      final activeWindow = _host._downloads
          .where((download) => download.batchId == job.jobId && _windowOccupyingStatus(download.status))
          .length;
      var slots = _OfflineDownloadActorCore._rollingWindowSize - activeWindow;

      if (slots <= 0) {
        return;
      }

      if (job.kind == 'artist') {
        await _host._discoverArtistJobItems(job, targetUnmaterialized: slots);
      }

      final items = _jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[];
      final candidates = items
          .where(
            (item) =>
                !item.materialized &&
                item.status == OfflineDownloadStatus.queued &&
                !_host._downloadQueuedOrAvailable(_host.find(job.serverBaseUrl, item.serverTrackId)),
          )
          .take(slots)
          .toList(growable: false);

      if (candidates.isEmpty) {
        await _refreshJobCounts(job.jobId);

        return;
      }

      await _host._materializeJobItems(job, candidates);
    } finally {
      developer.Timeline.finishSync();
    }
  }

  Future<void> _refreshJobCounts(String jobId) async {
    final job = _jobById(jobId);
    if (job == null) {
      return;
    }

    final items = _jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[];
    final sources = _jobSourcesByJobId[jobId] ?? const <OfflineDownloadJobSource>[];
    final completed = items.where((item) => item.status == OfflineDownloadStatus.downloaded).length;
    final failed = items
        .where((item) => item.status == OfflineDownloadStatus.failed || item.status == OfflineDownloadStatus.corrupt)
        .length;
    final canceled = items.where((item) => item.status == OfflineDownloadStatus.canceled).length;
    final materialized = items.where((item) => item.materialized).length;
    final active = items.any((item) => _windowOccupyingStatus(item.status));
    final paused = items.any((item) => item.status == OfflineDownloadStatus.paused);
    final pendingItems = items.any((item) => !item.materialized && item.status == OfflineDownloadStatus.queued);
    final pendingSources = sources.any((source) => source.status == OfflineDownloadStatus.queued);
    final sourceFailures = sources.where((source) => source.status == OfflineDownloadStatus.failed).length;
    final done = !active && !pendingItems && !pendingSources;
    final OfflineDownloadStatus status;

    if (job.status == OfflineDownloadStatus.paused || job.status == OfflineDownloadStatus.canceled) {
      status = job.status;
    } else if (paused) {
      status = OfflineDownloadStatus.paused;
    } else if (done) {
      if (failed + sourceFailures > 0) {
        status = OfflineDownloadStatus.failed;
      } else if (canceled > 0 && completed == 0) {
        status = OfflineDownloadStatus.canceled;
      } else {
        status = OfflineDownloadStatus.downloaded;
      }
    } else if (active) {
      status = OfflineDownloadStatus.downloading;
    } else {
      status = OfflineDownloadStatus.queued;
    }

    final updated = job.copyWith(
      status: status,
      updatedAt: DateTime.now(),
      discoveredCount: items.length,
      completedCount: completed,
      failedCount: failed + sourceFailures,
      materializedCount: materialized,
    );

    if (updated.status == OfflineDownloadStatus.downloaded) {
      await _deleteRollingJob(jobId);

      return;
    }

    if (job.status == updated.status &&
        job.discoveredCount == updated.discoveredCount &&
        job.completedCount == updated.completedCount &&
        job.failedCount == updated.failedCount &&
        job.materializedCount == updated.materializedCount &&
        job.totalCount == updated.totalCount) {
      return;
    }

    _jobs = _jobs.map((item) => item.jobId == jobId ? updated : item).toList(growable: false);
    await _host._storage.upsertDownloadJob(updated);
    await _host._upsertBatch(
      OfflineDownloadBatch(
        batchId: updated.jobId,
        serverBaseUrl: updated.serverBaseUrl,
        status: updated.status,
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
        totalCount: updated.totalCount > 0 ? updated.totalCount : updated.discoveredCount,
        completedCount: updated.completedCount,
        failedCount: updated.failedCount,
        label: updated.label,
      ),
    );

    _host._emitJobs();
  }

  bool _windowOccupyingStatus(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.removing => true,
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => false,
    };
  }

  bool _terminalStatus(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => true,
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.removing => false,
    };
  }

  bool _jobBlocksNewQueue(OfflineDownloadJob job) {
    return switch (job.status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating ||
      OfflineDownloadStatus.downloaded ||
      OfflineDownloadStatus.removing => true,
      OfflineDownloadStatus.paused ||
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled => false,
    };
  }

  OfflineDownloadJob? _pausedParentJob(OfflineTrackDownload download) {
    final batchId = download.batchId;

    if (batchId == null || batchId.trim().isEmpty) {
      return null;
    }

    final job = _jobById(batchId);

    if (job == null || job.status != OfflineDownloadStatus.paused) {
      return null;
    }

    return job;
  }

  OfflineDownloadJob _chooseRollingJobToKeep(List<OfflineDownloadJob> jobs) {
    final sorted = List<OfflineDownloadJob>.from(jobs);

    int compareJobsToKeep(OfflineDownloadJob left, OfflineDownloadJob right) {
      final rank = _jobKeepRank(right.status).compareTo(_jobKeepRank(left.status));

      if (rank != 0) {
        return rank;
      }

      final completed = right.completedCount.compareTo(left.completedCount);

      if (completed != 0) {
        return completed;
      }

      final materialized = right.materializedCount.compareTo(left.materializedCount);

      if (materialized != 0) {
        return materialized;
      }

      return right.updatedAt.compareTo(left.updatedAt);
    }

    sorted.sort(compareJobsToKeep);

    return sorted.first;
  }

  int _jobKeepRank(OfflineDownloadStatus status) {
    return switch (status) {
      OfflineDownloadStatus.queued ||
      OfflineDownloadStatus.preparing ||
      OfflineDownloadStatus.downloading ||
      OfflineDownloadStatus.validating => 4,
      OfflineDownloadStatus.paused => 3,
      OfflineDownloadStatus.downloaded => 2,
      OfflineDownloadStatus.failed ||
      OfflineDownloadStatus.corrupt ||
      OfflineDownloadStatus.canceled ||
      OfflineDownloadStatus.removing => 1,
    };
  }

  bool _jobMatchesRollingCollection(
    OfflineDownloadJob job, {
    String? profile,
    required String kind,
    required String serverBaseUrl,
    required String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) {
    if (job.kind != kind || job.serverBaseUrl != serverBaseUrl || job.profile != (profile ?? _host._queueProfile)) {
      return false;
    }

    final sourceSignature = _idSignature(sourceIds);

    if (sourceSignature.isNotEmpty) {
      final jobSourceSignature = _idSignature(
        (_jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[]).map((source) => source.sourceId),
      );

      return jobSourceSignature.isNotEmpty && jobSourceSignature == sourceSignature;
    }

    final trackSignature = _idSignature(trackIds);

    if (trackSignature.isNotEmpty) {
      final jobTrackSignature = _idSignature(
        (_jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).map((item) => item.serverTrackId),
      );

      return jobTrackSignature.isNotEmpty && jobTrackSignature == trackSignature;
    }

    final normalizedLabel = _normalizedJobLabel(label);

    return normalizedLabel.isNotEmpty && _normalizedJobLabel(job.label) == normalizedLabel;
  }

  String? _rollingJobCollectionKey(OfflineDownloadJob job) {
    final sourceSignature = _idSignature(
      (_jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[]).map((source) => source.sourceId),
    );

    if (sourceSignature.isNotEmpty) {
      return '${job.serverBaseUrl}\n${job.kind}\n${job.profile}\nsources:$sourceSignature';
    }

    final trackSignature = _idSignature(
      (_jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[]).map((item) => item.serverTrackId),
    );

    if (trackSignature.isNotEmpty) {
      return '${job.serverBaseUrl}\n${job.kind}\n${job.profile}\ntracks:$trackSignature';
    }

    final label = _normalizedJobLabel(job.label);

    if (label.isEmpty) {
      return null;
    }

    return '${job.serverBaseUrl}\n${job.kind}\n${job.profile}\nlabel:$label';
  }

  String _stableJobId(String kind, String signature) {
    final digest = sha1.convert(utf8.encode('${_host.connection.baseUrl}\n$kind\n$signature')).toString();

    return 'job_${kind}_$digest';
  }

  String _queueAttemptRequestId(String stableJobId) {
    _queueAttemptSequence += 1;
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    return '$stableJobId:$nonce:${_queueAttemptSequence.toRadixString(36)}';
  }

  String _rollingJobSignature({
    String profile = 'original',
    String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) {
    final sourceSignature = _idSignature(sourceIds);
    final prefix = profile == 'original' ? '' : '$profile:';

    if (sourceSignature.isNotEmpty) {
      return '${prefix}sources:$sourceSignature';
    }

    final trackSignature = _idSignature(trackIds);

    if (trackSignature.isNotEmpty) {
      return '${prefix}tracks:$trackSignature';
    }

    return '${prefix}label:${_normalizedJobLabel(label)}';
  }

  String _idSignature(Iterable<String> ids) {
    final normalized = ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList(growable: false);

    normalized.sort();

    return normalized.join('|');
  }

  String _normalizedJobLabel(String? label) {
    return label?.trim().toLowerCase() ?? '';
  }

  String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  String _downloadKey(OfflineTrackDownload download) {
    return _lookupKey(download.serverBaseUrl, _serverTrackId(download));
  }

  String _lookupKey(String serverBaseUrl, String trackId) {
    return '$serverBaseUrl\n$trackId';
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  bool _isRollingJob(String batchId) {
    return _jobs.any((job) => job.jobId == batchId);
  }

  OfflineDownloadJob? _jobById(String jobId) {
    for (final job in _jobs) {
      if (job.jobId == jobId) {
        return job;
      }
    }

    return null;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _RollingDownloadJobsFacade {
  _RollingDownloadJobs get _ownerRolling;

  List<OfflineDownloadJob> get _jobs => _ownerRolling._jobs;

  set _jobs(List<OfflineDownloadJob> value) => _ownerRolling._jobs = value;

  Map<String, List<OfflineDownloadJobItem>> get _jobItemsByJobId => _ownerRolling._jobItemsByJobId;

  Map<String, List<OfflineDownloadJobSource>> get _jobSourcesByJobId => _ownerRolling._jobSourcesByJobId;

  set _queueAttemptSequence(int value) => _ownerRolling._queueAttemptSequence = value;

  Future<int> _queueRollingBatch(DownloadBatchManifest manifest, {String? label}) =>
      _ownerRolling._queueRollingBatch(manifest, label: label);

  Future<void> _insertRollingJob(
    OfflineDownloadJob job, {
    List<OfflineDownloadJobItem> items = const <OfflineDownloadJobItem>[],
    List<OfflineDownloadJobSource> sources = const <OfflineDownloadJobSource>[],
  }) => _ownerRolling._insertRollingJob(job, items: items, sources: sources);

  Future<OfflineDownloadJob?> _reuseOrClearRollingJob({
    String? profile,
    required String jobId,
    required String kind,
    required String serverBaseUrl,
    required String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) => _ownerRolling._reuseOrClearRollingJob(
    profile: profile,
    jobId: jobId,
    kind: kind,
    serverBaseUrl: serverBaseUrl,
    label: label,
    trackIds: trackIds,
    sourceIds: sourceIds,
  );

  Future<void> _reconcileLoadedRollingJobs() => _ownerRolling._reconcileLoadedRollingJobs();

  Future<void> _pruneDuplicateRollingJobs() => _ownerRolling._pruneDuplicateRollingJobs();

  Future<void> _deleteRollingJob(String jobId, {bool removePendingDownloads = false}) =>
      _ownerRolling._deleteRollingJob(jobId, removePendingDownloads: removePendingDownloads);

  void _forgetRollingJob(String jobId) => _ownerRolling._forgetRollingJob(jobId);

  Future<bool> _deleteRollingJobIfAbandoned(String jobId) => _ownerRolling._deleteRollingJobIfAbandoned(jobId);

  Future<void> _topUpRollingJobsForCurrentServer() => _ownerRolling._topUpRollingJobsForCurrentServer();

  Future<void> _topUpRollingJob(OfflineDownloadJob job) => _ownerRolling._topUpRollingJob(job);

  Future<void> _refreshJobCounts(String jobId) => _ownerRolling._refreshJobCounts(jobId);

  bool _terminalStatus(OfflineDownloadStatus status) => _ownerRolling._terminalStatus(status);

  bool _jobBlocksNewQueue(OfflineDownloadJob job) => _ownerRolling._jobBlocksNewQueue(job);

  OfflineDownloadJob? _pausedParentJob(OfflineTrackDownload download) => _ownerRolling._pausedParentJob(download);

  String _stableJobId(String kind, String signature) => _ownerRolling._stableJobId(kind, signature);

  String _queueAttemptRequestId(String stableJobId) => _ownerRolling._queueAttemptRequestId(stableJobId);

  String _rollingJobSignature({
    String profile = 'original',
    String? label,
    Iterable<String> trackIds = const <String>[],
    Iterable<String> sourceIds = const <String>[],
  }) => _ownerRolling._rollingJobSignature(profile: profile, label: label, trackIds: trackIds, sourceIds: sourceIds);

  String _normalizedJobLabel(String? label) => _ownerRolling._normalizedJobLabel(label);

  String _serverTrackId(OfflineTrackDownload download) => _ownerRolling._serverTrackId(download);

  String _downloadKey(OfflineTrackDownload download) => _ownerRolling._downloadKey(download);

  String _lookupKey(String serverBaseUrl, String trackId) => _ownerRolling._lookupKey(serverBaseUrl, trackId);

  String? _nonEmpty(String? value) => _ownerRolling._nonEmpty(value);

  bool _isRollingJob(String batchId) => _ownerRolling._isRollingJob(batchId);

  OfflineDownloadJob? _jobById(String jobId) => _ownerRolling._jobById(jobId);
}
