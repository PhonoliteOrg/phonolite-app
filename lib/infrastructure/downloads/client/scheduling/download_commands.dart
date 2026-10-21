part of 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';

class _DownloadCommands {
  final _OfflineDownloadActorCore _host;
  final Map<String, SendPort> _activeCancelPorts = <String, SendPort>{};
  final Set<String> _pausedServerUrls = <String>{};

  _DownloadCommands(this._host);

  Future<void> pauseDownload(OfflineTrackDownload download) async {
    final current = _host.find(download.serverBaseUrl, _host._serverTrackId(download));

    if (current == null || !_host._canPause(current.status)) {
      return;
    }

    final key = _host._downloadKey(current);

    _host._cancelRequested.add(key);
    _activeCancelPorts[key]?.send(null);

    await _host._replace(
      current.copyWith(status: OfflineDownloadStatus.paused, updatedAt: DateTime.now(), error: null),
      persist: true,
    );
  }

  Future<void> resumeDownload(OfflineTrackDownload download) async {
    final current = _host.find(download.serverBaseUrl, _host._serverTrackId(download));
    if (current == null) {
      return;
    }

    final parentJob = _host._pausedParentJob(current);

    if (parentJob != null &&
        (current.status == OfflineDownloadStatus.paused || current.status == OfflineDownloadStatus.queued)) {
      await _host.resumeDownloadJob(parentJob);

      return;
    }

    if (!_host._canResume(current.status)) {
      return;
    }

    _pausedServerUrls.remove(current.serverBaseUrl);

    if (current.status == OfflineDownloadStatus.corrupt) {
      await _host._deleteIfExists(current.partialPath);
    }

    await _host._replace(
      current.copyWith(
        status: OfflineDownloadStatus.queued,
        updatedAt: DateTime.now(),
        partialPath: current.status == OfflineDownloadStatus.corrupt ? null : current.partialPath,
        bytesDownloaded: current.status == OfflineDownloadStatus.corrupt ? 0 : current.bytesDownloaded,
        error: null,
        retryCount: current.retryCount + 1,
      ),
      persist: true,
    );

    _host._schedule();
  }

  Future<void> retryDownload(OfflineTrackDownload download) async {
    await _host.resumeDownload(download);
  }

  Future<void> cancelDownload(OfflineTrackDownload download) async {
    final current = _host.find(download.serverBaseUrl, _host._serverTrackId(download));

    if (current == null || current.status == OfflineDownloadStatus.downloaded) {
      return;
    }

    final key = _host._downloadKey(current);

    _host._cancelRequested.add(key);
    _activeCancelPorts[key]?.send(null);

    if (!_host._active.containsKey(key)) {
      await _host._deleteIfExists(current.partialPath);
    }

    await _host._replace(
      current.copyWith(
        status: OfflineDownloadStatus.canceled,
        updatedAt: DateTime.now(),
        partialPath: null,
        bytesDownloaded: 0,
        error: null,
      ),
      persist: true,
    );
  }

  Future<void> pauseDownloadsForServer(String serverBaseUrl) async {
    final normalized = serverBaseUrl.trim();

    if (normalized.isEmpty) {
      return;
    }

    _pausedServerUrls.add(normalized);

    final now = DateTime.now();
    var changed = false;
    final pausedJobs = <OfflineDownloadJob>[];
    final updatedJobs = <OfflineDownloadJob>[];

    for (final job in _host._jobs) {
      if (job.serverBaseUrl != normalized || !_host._canPause(job.status)) {
        updatedJobs.add(job);
        continue;
      }

      final updated = job.copyWith(status: OfflineDownloadStatus.paused, updatedAt: now);

      pausedJobs.add(updated);
      updatedJobs.add(updated);
    }

    _host._jobs = updatedJobs.toList(growable: false);

    if (pausedJobs.isNotEmpty) {
      await _host._storage.upsertDownloadJobs(pausedJobs);
      _host._emitJobs();
      changed = true;
    }

    for (final download in _host._downloads) {
      if (download.serverBaseUrl != normalized || !_host._canPause(download.status)) {
        continue;
      }

      final key = _host._downloadKey(download);

      _host._cancelRequested.add(key);
      _activeCancelPorts[key]?.send(null);

      await _host._replace(
        download.copyWith(status: OfflineDownloadStatus.paused, updatedAt: now, error: null),
        persist: true,
      );
      changed = true;
    }

    if (changed) {
      AppLogger.status('Paused downloads for $normalized');
    }
  }

  Future<void> resumePausedForCurrentServer() async {
    await _host._ensureLoaded();

    if (_host.connection.token == null || _host.connection.token!.isEmpty) {
      return;
    }

    final baseUrl = _host.connection.baseUrl;

    _pausedServerUrls.remove(baseUrl);

    final now = DateTime.now();
    var changed = false;
    final retryableJobs = _host._jobs
        .where(
          (job) =>
              job.serverBaseUrl == baseUrl &&
              job.status != OfflineDownloadStatus.canceled &&
              job.status != OfflineDownloadStatus.removing,
        )
        .map((job) => job.jobId)
        .toSet();

    for (final download in _host._downloads) {
      if (download.serverBaseUrl != baseUrl ||
          (download.status != OfflineDownloadStatus.paused &&
              !(retryableJobs.contains(download.batchId) &&
                  (download.status == OfflineDownloadStatus.failed ||
                      download.status == OfflineDownloadStatus.corrupt)))) {
        continue;
      }

      await _host._replace(
        download.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now, error: null),
        persist: true,
      );
      changed = true;
    }

    for (final jobId in retryableJobs) {
      final items = _host._jobItemsByJobId[jobId] ?? const <OfflineDownloadJobItem>[];
      final retryIds = items
          .where(
            (item) =>
                item.status == OfflineDownloadStatus.failed ||
                item.status == OfflineDownloadStatus.corrupt ||
                item.status == OfflineDownloadStatus.paused,
          )
          .map((item) => item.serverTrackId)
          .toList(growable: false);

      await _host._markJobItems(jobId, retryIds, OfflineDownloadStatus.queued);

      final sources = _host._jobSourcesByJobId[jobId] ?? const <OfflineDownloadJobSource>[];
      final retriedSources = [
        for (final source in sources)
          if (source.status != OfflineDownloadStatus.queued &&
              source.status != OfflineDownloadStatus.downloaded &&
              source.status != OfflineDownloadStatus.canceled)
            source.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now, error: null),
      ];

      if (retriedSources.isNotEmpty) {
        await _host._storage.saveDownloadJobDiscovery(items: const [], sources: retriedSources);

        final byId = {for (final source in retriedSources) source.sourceId: source};

        _host._jobSourcesByJobId[jobId] = [
          for (final source in _host._jobSourcesByJobId[jobId] ?? sources) byId[source.sourceId] ?? source,
        ];
      }
    }

    final resumedJobs = <OfflineDownloadJob>[];
    final updatedJobs = <OfflineDownloadJob>[];

    for (final job in _host._jobs) {
      if (job.serverBaseUrl != baseUrl ||
          (job.status != OfflineDownloadStatus.paused &&
              job.status != OfflineDownloadStatus.failed &&
              job.status != OfflineDownloadStatus.corrupt)) {
        updatedJobs.add(job);
        continue;
      }

      final updated = job.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now, error: null);

      resumedJobs.add(updated);
      updatedJobs.add(updated);
    }

    _host._jobs = updatedJobs.toList(growable: false);

    if (resumedJobs.isNotEmpty) {
      await _host._storage.upsertDownloadJobs(resumedJobs);
      _host._emitJobs();
      changed = true;
    }

    for (final jobId in retryableJobs) {
      await _host._refreshJobCounts(jobId);
    }

    if (changed) {
      AppLogger.status('Resuming paused downloads for $baseUrl');
    }

    // Restored queued jobs also need discovery/materialization after sign-in,
    // even when no staged track happened to be paused at shutdown.
    _host._schedule();
  }

  Future<void> pauseDownloadJob(OfflineDownloadJob job) async {
    final current = _host._jobById(job.jobId);

    if (current == null || current.status == OfflineDownloadStatus.paused) {
      return;
    }

    final updated = current.copyWith(status: OfflineDownloadStatus.paused, updatedAt: DateTime.now());

    _host._jobs = _host._jobs.map((item) => item.jobId == updated.jobId ? updated : item).toList(growable: false);
    await _host._storage.upsertDownloadJob(updated);
    _host._emitJobs();

    final activeDownloads = _host._downloads
        .where(
          (download) =>
              download.batchId == updated.jobId &&
              (_host._active.containsKey(_host._downloadKey(download)) || _host._activeDownloadStatus(download.status)),
        )
        .toList(growable: false);

    for (final download in activeDownloads) {
      await _host.pauseDownload(download);
    }
  }

  Future<void> resumeDownloadJob(OfflineDownloadJob job) async {
    final current = _host._jobById(job.jobId);

    if (current == null || current.status != OfflineDownloadStatus.paused) {
      return;
    }

    _pausedServerUrls.remove(current.serverBaseUrl);

    final now = DateTime.now();
    final pausedDownloads = _host._downloads
        .where((download) => download.batchId == current.jobId && download.status == OfflineDownloadStatus.paused)
        .toList(growable: false);
    final requeuedDownloads = <OfflineTrackDownload>[
      for (final download in pausedDownloads)
        download.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now, error: null),
    ];

    if (requeuedDownloads.isNotEmpty) {
      _host._replaceManyInMemory(requeuedDownloads);
      await _host._storage.upsertDownloads(requeuedDownloads);
      await _host._markJobItems(
        current.jobId,
        requeuedDownloads.map(_host._serverTrackId),
        OfflineDownloadStatus.queued,
        materialized: true,
        tracksById: {for (final download in requeuedDownloads) _host._serverTrackId(download): download.track},
      );
    }

    final updated = current.copyWith(status: OfflineDownloadStatus.queued, updatedAt: now);

    _host._jobs = _host._jobs.map((item) => item.jobId == updated.jobId ? updated : item).toList(growable: false);
    await _host._storage.upsertDownloadJob(updated);
    _host._emitJobs();

    _host._schedule();
  }

  Future<void> cancelDownloadJob(OfflineDownloadJob job) async {
    final current = _host._jobById(job.jobId);
    if (current == null) {
      return;
    }

    await _host._deleteRollingJob(current.jobId, removePendingDownloads: true);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadCommandsFacade {
  _DownloadCommands get _ownerControl;

  Map<String, SendPort> get _activeCancelPorts => _ownerControl._activeCancelPorts;

  Set<String> get _pausedServerUrls => _ownerControl._pausedServerUrls;

  Future<void> pauseDownload(OfflineTrackDownload download) => _ownerControl.pauseDownload(download);

  Future<void> resumeDownload(OfflineTrackDownload download) => _ownerControl.resumeDownload(download);

  Future<void> retryDownload(OfflineTrackDownload download) => _ownerControl.retryDownload(download);

  Future<void> cancelDownload(OfflineTrackDownload download) => _ownerControl.cancelDownload(download);

  Future<void> pauseDownloadsForServer(String serverBaseUrl) => _ownerControl.pauseDownloadsForServer(serverBaseUrl);

  Future<void> resumePausedForCurrentServer() => _ownerControl.resumePausedForCurrentServer();

  Future<void> pauseDownloadJob(OfflineDownloadJob job) => _ownerControl.pauseDownloadJob(job);

  Future<void> resumeDownloadJob(OfflineDownloadJob job) => _ownerControl.resumeDownloadJob(job);

  Future<void> cancelDownloadJob(OfflineDownloadJob job) => _ownerControl.cancelDownloadJob(job);
}
