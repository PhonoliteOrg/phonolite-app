part of '../offline_download_client.dart';

class _DownloadScheduler {
  final _OfflineDownloadActorCore _host;
  Future<void>? _topUpFuture;
  bool _topUpRequested = false;
  final Map<String, Future<void>> _active = <String, Future<void>>{};
  String? _lastScheduledQueueGroup;
  bool _loaded = false;
  bool _resettingLocalData = false;

  _DownloadScheduler(this._host);

  void _schedule() {
    _scheduleTopUp();
    _scheduleQueuedDownloads();
  }

  void _scheduleTopUp() {
    if (_resettingLocalData || _host._disposed) {
      return;
    }

    _topUpRequested = true;

    if (_topUpFuture != null) {
      return;
    }

    void finishTopUp() {
      _topUpFuture = null;

      if (_topUpRequested && !_host._disposed && !_resettingLocalData) {
        _scheduleTopUp();
      }
    }

    Future<void> drainTopUps() async {
      do {
        _topUpRequested = false;
        await _host._topUpRollingJobsForCurrentServer();
      } while (_topUpRequested && !_host._disposed && !_resettingLocalData);
    }

    _topUpFuture = drainTopUps().whenComplete(finishTopUp);
    unawaited(_topUpFuture);
  }

  void _scheduleQueuedDownloads() {
    if (!_loaded || _host._disposed) {
      return;
    }

    if (_resettingLocalData) {
      return;
    }

    if (_host.connection.token == null || _host.connection.token!.isEmpty) {
      return;
    }

    final baseUrl = _host.connection.baseUrl;

    if (_host._pausedServerUrls.contains(baseUrl)) {
      return;
    }

    final activeForServer = _active.keys.where((key) => key.startsWith('$baseUrl\n')).length;
    var slots = _OfflineDownloadActorCore.maxParallelDownloadsPerServer - activeForServer;

    if (slots <= 0) {
      return;
    }

    final candidates = _host._downloads
        .where(
          (download) =>
              download.serverBaseUrl == baseUrl &&
              download.status == OfflineDownloadStatus.queued &&
              !_active.containsKey(_host._downloadKey(download)) &&
              !_queuedDownloadBlockedByPausedJob(download),
        )
        .toList();

    candidates.sort(_compareQueuedForScheduling);

    final groups = <String, List<OfflineTrackDownload>>{};

    for (final download in candidates) {
      groups.putIfAbsent(_queueGroupKey(download), () => <OfflineTrackDownload>[]).add(download);
    }

    while (slots > 0 && groups.isNotEmpty) {
      final groupKey = _nextQueueGroupKey(groups.keys.toList(growable: false));
      final group = groups[groupKey]!;
      final download = group.removeAt(0);

      if (group.isEmpty) {
        groups.remove(groupKey);
      }

      _startQueuedDownload(download);
      _lastScheduledQueueGroup = groupKey;
      slots -= 1;
    }
  }

  void _startQueuedDownload(OfflineTrackDownload download) {
    final key = _host._downloadKey(download);

    _host._clearObsoleteStopMarkersForQueue(download);

    void finishDownload() {
      _active.remove(key);
      _host._activeCancelPorts.remove(key);
      _host._cancelRequested.remove(key);

      _schedule();
    }

    final future = _host._runDownload(download).whenComplete(finishDownload);

    _active[key] = future;
    unawaited(future);
  }

  String _nextQueueGroupKey(List<String> groupKeys) {
    final last = _lastScheduledQueueGroup;
    if (last == null) {
      return groupKeys.first;
    }

    final lastIndex = groupKeys.indexOf(last);

    if (lastIndex < 0) {
      return groupKeys.first;
    }

    return groupKeys[(lastIndex + 1) % groupKeys.length];
  }

  String _queueGroupKey(OfflineTrackDownload download) {
    final batchId = download.batchId;

    if (batchId != null && batchId.trim().isNotEmpty) {
      return 'batch:${download.serverBaseUrl}\n$batchId';
    }

    return 'track:${_host._downloadKey(download)}';
  }

  bool _queuedDownloadBlockedByPausedJob(OfflineTrackDownload download) {
    final batchId = download.batchId;

    if (batchId == null || batchId.trim().isEmpty) {
      return false;
    }

    final job = _host._jobById(batchId);

    return job != null && job.status == OfflineDownloadStatus.paused;
  }

  int _compareQueuedForScheduling(OfflineTrackDownload left, OfflineTrackDownload right) {
    final priority = right.priority.compareTo(left.priority);

    if (priority != 0) {
      return priority;
    }

    return left.createdAt.compareTo(right.createdAt);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadSchedulerFacade {
  _DownloadScheduler get _ownerScheduler;

  Future<void>? get _topUpFuture => _ownerScheduler._topUpFuture;

  set _topUpRequested(bool value) => _ownerScheduler._topUpRequested = value;

  Map<String, Future<void>> get _active => _ownerScheduler._active;

  set _lastScheduledQueueGroup(String? value) => _ownerScheduler._lastScheduledQueueGroup = value;

  bool get _loaded => _ownerScheduler._loaded;

  set _loaded(bool value) => _ownerScheduler._loaded = value;

  bool get _resettingLocalData => _ownerScheduler._resettingLocalData;

  set _resettingLocalData(bool value) => _ownerScheduler._resettingLocalData = value;

  void _schedule() => _ownerScheduler._schedule();

  void _scheduleTopUp() => _ownerScheduler._scheduleTopUp();

  void _scheduleQueuedDownloads() => _ownerScheduler._scheduleQueuedDownloads();

  bool _queuedDownloadBlockedByPausedJob(OfflineTrackDownload download) =>
      _ownerScheduler._queuedDownloadBlockedByPausedJob(download);
}
