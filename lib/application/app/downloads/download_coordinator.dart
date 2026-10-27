part of '../app_controller.dart';

class _DownloadCoordinator {
  final AppController _host;

  _DownloadCoordinator(this._host);

  List<OfflineTrackDownload> get availableOfflineDownloads =>
      _host._offlineDownloadManager.downloads.where(_offlineDownloadAvailable).toList(growable: false);

  OfflineTrackDownload? offlineDownloadForTrack(String trackId) {
    return _host._offlineDownloadManager.findForCurrentServer(trackId) ??
        _host._offlineDownloadManager.downloads
            .where((download) => download.localTrackId == trackId || download.track.localId == trackId)
            .firstOrNull;
  }

  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) {
    final currentServer = _host._offlineDownloadManager.findForCurrentServer(trackId);

    if (currentServer != null && _offlineDownloadAvailable(currentServer)) {
      return currentServer;
    }

    final local = _host._offlineDownloadManager.downloads
        .where(
          (download) =>
              (download.localTrackId == trackId || download.track.localId == trackId) &&
              _offlineDownloadAvailable(download),
        )
        .firstOrNull;

    if (local != null && _offlineDownloadAvailable(local)) {
      return local;
    }

    return null;
  }

  Track? serverTrackForCurrentServer(Track track) {
    if (!_host._authState.isAuthorized) {
      return null;
    }

    return TrackSourceResolver.knownServerTrack(
      track,
      serverBaseUrl: _host.connection.baseUrl,
      downloads: _host._offlineDownloadManager.downloads,
    );
  }

  Future<void> downloadTrack(Track track) async {
    if (!_host._authState.isAuthorized) {
      _host._pushMessage('Connect to a server before downloading ${track.title}.', level: LogLevel.warning);

      return;
    }

    try {
      final queuedCount = await _host._offlineDownloadManager.downloadTrack(track);

      if (queuedCount > 0) {
        _host._pushMessage('Queued ${track.title} for download.');
      } else {
        _host._pushMessage('${track.title} is already downloaded or queued.');
      }
    } catch (err) {
      _host._pushMessage('Failed to queue ${track.title}: $err', level: LogLevel.warning);
    }
  }

  Future<void> downloadAlbum(Album album, List<Track> tracks) async {
    await _downloadTrackCollection(
      tracks,
      label: album.title,
      kind: 'album',
      sourceId: album.id,
      emptyMessage: 'No tracks found to download for ${album.title}.',
    );
  }

  Future<void> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async {
    if (!_host._authState.isAuthorized) {
      throw StateError('Connect to a server before downloading a playlist.');
    }

    try {
      await _host._offlineDownloadManager.downloadPlaylist(
        playlist,
        tracks,
        name: name,
        description: description,
        imageEdit: imageEdit,
      );

      _host._pushMessage('Saved local copy of $name.');
    } catch (err) {
      _host._pushMessage('Failed to download playlist $name: $err', level: LogLevel.warning);

      rethrow;
    }
  }

  Future<void> downloadArtist(Artist artist, List<Album> albums) async {
    if (!_host._requireServer('downloading ${artist.name}')) {
      return;
    }

    if (albums.isEmpty) {
      _host._pushMessage('No albums found to download for ${artist.name}.');

      return;
    }

    try {
      final queuedCount = await _host._offlineDownloadManager.queueArtist(artist, albums);

      if (queuedCount == 0) {
        _host._pushMessage('All tracks are already downloaded or queued for ${artist.name}.');

        return;
      }

      final queuedTrackLabel = queuedCount == 1 ? 'track' : 'tracks';

      _host._pushMessage('Queued $queuedCount $queuedTrackLabel for ${artist.name}.');
    } catch (err) {
      _host._pushMessage('Failed to queue downloads for ${artist.name}: $err', level: LogLevel.warning);
    }
  }

  Future<void> removeOfflineTrack(String trackId) async {
    final download = _host.offlineDownloadForTrack(trackId);
    if (download == null) {
      return;
    }

    await _host.removeOfflineDownload(download);
  }

  Future<void> pauseOfflineDownload(OfflineTrackDownload download) async {
    await _host._offlineDownloadManager.pauseDownload(download);
  }

  Future<void> resumeOfflineDownload(OfflineTrackDownload download) async {
    await _host._offlineDownloadManager.resumeDownload(download);
  }

  Future<void> pauseOfflineDownloadJob(OfflineDownloadJob job) async {
    await _host._offlineDownloadManager.pauseDownloadJob(job);

    final label = job.label?.trim();

    _host._pushMessage('Paused downloads for ${label == null || label.isEmpty ? job.kind : label}.');
  }

  Future<void> resumeOfflineDownloadJob(OfflineDownloadJob job) async {
    await _host._offlineDownloadManager.resumeDownloadJob(job);

    final label = job.label?.trim();

    _host._pushMessage('Resumed downloads for ${label == null || label.isEmpty ? job.kind : label}.');
  }

  Future<void> pauseAllOfflineDownloads() async {
    final serverBaseUrls = <String>{
      for (final download in _host._offlineDownloadManager.downloads)
        if (_offlineDownloadPausable(download.status)) download.serverBaseUrl.trim(),
      for (final job in _host._offlineDownloadManager.jobs)
        if (_offlineDownloadPausable(job.status)) job.serverBaseUrl.trim(),
    };

    serverBaseUrls.removeWhere((baseUrl) => baseUrl.isEmpty);

    if (serverBaseUrls.isEmpty) {
      _host._pushMessage('No active downloads to pause.');

      return;
    }

    for (final serverBaseUrl in serverBaseUrls) {
      await _host._offlineDownloadManager.pauseDownloadsForServer(serverBaseUrl);
    }

    _host._pushMessage('Paused downloads.');
  }

  Future<void> retryOfflineDownload(OfflineTrackDownload download) async {
    await _host._offlineDownloadManager.retryDownload(download);
  }

  Future<void> cancelOfflineDownload(OfflineTrackDownload download) async {
    await _host._offlineDownloadManager.cancelDownload(download);
  }

  Future<void> cancelOfflineDownloadJob(OfflineDownloadJob job) async {
    await _host._offlineDownloadManager.cancelDownloadJob(job);

    final label = job.label?.trim();

    _host._pushMessage('Canceled downloads for ${label == null || label.isEmpty ? job.kind : label}.');
  }

  Future<void> removeOfflineDownload(OfflineTrackDownload download) async {
    await _host.removeOfflineDownloads(<OfflineTrackDownload>[download], label: download.track.title);
  }

  Future<void> removeOfflineDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final downloadList = downloads.toList(growable: false);
    final fallbackLabel = downloadList.length == 1 ? downloadList.single.track.title : 'selection';

    await _removeOfflineDownloads(downloadList, label: label ?? fallbackLabel, scope: scope);
  }

  Future<void> removeDownloadedTrack(Track track) async {
    await _host.removeDownloadedTracks(<Track>[track], label: track.title);
  }

  Future<void> removeDownloadedTracks(
    Iterable<Track> tracks, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final trackList = tracks.toList(growable: false);
    final downloads = <OfflineTrackDownload>[for (final track in trackList) ..._downloadsForTrackRemoval(track)];

    if (downloads.isEmpty) {
      final trimmedLabel = label?.trim();
      final String messageLabel;

      if (trimmedLabel == null || trimmedLabel.isEmpty) {
        messageLabel = trackList.length == 1 ? trackList.single.title : 'selection';
      } else {
        messageLabel = trimmedLabel;
      }

      _host._pushMessage('No downloaded file available to remove for $messageLabel.', level: LogLevel.warning);

      return;
    }

    final fallbackLabel = trackList.length == 1 ? trackList.single.title : 'selection';

    await _removeOfflineDownloads(downloads, label: label ?? fallbackLabel, scope: scope);
  }

  Future<void> clearFailedOfflineDownloads() async {
    await _host._offlineDownloadManager.clearFailedAndCorrupt();
  }

  Future<void> resumePausedOfflineDownloads() async {
    if (!_host._requireServer('resuming paused downloads')) {
      return;
    }

    final baseUrl = _host.connection.baseUrl;
    final pausedDownloads = _host._offlineDownloadManager.downloads
        .where((download) => download.serverBaseUrl == baseUrl && download.status == OfflineDownloadStatus.paused)
        .length;
    final pausedJobs = _host._offlineDownloadManager.jobs
        .where((job) => job.serverBaseUrl == baseUrl && job.status == OfflineDownloadStatus.paused)
        .toList(growable: false);

    if (pausedDownloads == 0 && pausedJobs.isEmpty) {
      _host._pushMessage('No paused downloads to resume.');

      return;
    }

    for (final job in pausedJobs) {
      await _host._offlineDownloadManager.resumeDownloadJob(job);
    }

    await _host._offlineDownloadManager.resumePausedForCurrentServer();

    _host._pushMessage('Resumed paused downloads.');
  }

  Future<void> clearUnfinishedOfflineDownloads() async {
    try {
      await _host._offlineDownloadManager.clearUnfinishedDownloads();
      await _host.loadOfflineStorageLocations();

      _host._pushMessage('Cleared unfinished download jobs and partial cache.');
    } catch (err) {
      _host._pushMessage('Failed to clear download jobs and cache: $err', level: LogLevel.warning);
    }
  }

  bool _offlineDownloadAvailable(OfflineTrackDownload download) {
    if (!download.isDownloaded || download.filePath == null) {
      return false;
    }

    if (kIsWeb) {
      return false;
    }

    return download.filePath!.isNotEmpty;
  }

  List<OfflineTrackDownload> _downloadsForTrackRemoval(Track track) {
    final localId =
        _nonEmptyString(track.localId) ??
        _nonEmptyString(_host._offlineDownloadManager.findLocal(track.id)?.localTrackId);
    final isLocalLibraryTrack = localId != null && track.id == localId;

    if (isLocalLibraryTrack) {
      return _host._offlineDownloadManager.downloads
          .where((download) => _downloadLocalId(download) == localId)
          .toList(growable: false);
    }

    final serverTrackId = _nonEmptyString(track.serverTrackId) ?? track.id;
    final currentServer =
        _host._offlineDownloadManager.findForCurrentServer(serverTrackId) ??
        _host._offlineDownloadManager.findForCurrentServer(track.id);
    if (currentServer != null) {
      return <OfflineTrackDownload>[currentServer];
    }

    final fallback = _host.availableOfflineDownloadForTrack(track.id);
    if (fallback == null) {
      return const <OfflineTrackDownload>[];
    }

    return <OfflineTrackDownload>[fallback];
  }

  Future<void> _removeOfflineDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    required String label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) async {
    final byKey = <String, OfflineTrackDownload>{
      for (final download in downloads) _offlineDownloadKey(download): download,
    };
    final uniqueDownloads = byKey.values.toList(growable: false);

    if (uniqueDownloads.isEmpty) {
      return;
    }

    final shouldStopPlayback = uniqueDownloads.any(_downloadMatchesCurrentLocalPlayback);

    if (shouldStopPlayback) {
      await _host.stop();
    }

    await _host._offlineDownloadManager.removeDownloads(uniqueDownloads, scope: scope);

    if (!shouldStopPlayback) {
      _pruneRemovedDownloadsFromOfflineQueue(uniqueDownloads);
    }

    final trimmedLabel = label.trim().isEmpty ? 'track' : label.trim();

    if (uniqueDownloads.length == 1) {
      _host._pushMessage('Removed download for $trimmedLabel from this device.');
    } else {
      _host._pushMessage('Removed ${uniqueDownloads.length} downloads for $trimmedLabel from this device.');
    }
  }

  void _pruneRemovedDownloadsFromOfflineQueue(List<OfflineTrackDownload> downloads) {
    if (_host._playbackState.queueSource != PlaybackQueueSource.offline || _host._playQueue.isEmpty) {
      return;
    }

    final nextQueue = _host._playQueue
        .where((track) => !downloads.any((download) => _downloadMatchesTrackIdentity(download, track)))
        .toList(growable: false);

    if (nextQueue.length == _host._playQueue.length) {
      return;
    }

    _host._playQueue = nextQueue;

    if (_host._playQueue.isEmpty) {
      _host._playIndex = 0;

      return;
    }

    final current = _host._playbackState.track;
    final currentIndex = current == null
        ? -1
        : _host._playQueue.indexWhere((track) => _sameTrackIdentity(track, current));

    if (currentIndex >= 0) {
      _host._playIndex = currentIndex;
    } else if (_host._playIndex >= _host._playQueue.length) {
      _host._playIndex = max(0, _host._playQueue.length - 1);
    }
  }

  bool _downloadMatchesCurrentLocalPlayback(OfflineTrackDownload download) {
    if (!_host._playbackState.isLocalPlayback) {
      return false;
    }

    final current = _host._playbackState.track;
    if (current == null) {
      return false;
    }

    return _downloadMatchesTrackIdentity(download, current);
  }

  bool _downloadMatchesTrackIdentity(OfflineTrackDownload download, Track track) {
    final localId = _downloadLocalId(download);

    if (localId != null && (track.id == localId || _nonEmptyString(track.localId) == localId)) {
      return true;
    }

    final serverTrackId = _serverTrackId(download);

    if (track.id != serverTrackId && track.serverTrackId != serverTrackId) {
      return false;
    }

    final serverBaseUrl = _nonEmptyString(track.serverBaseUrl);

    return serverBaseUrl == null || serverBaseUrl == download.serverBaseUrl;
  }

  bool _sameTrackIdentity(Track left, Track right) {
    if (left.id == right.id) {
      return true;
    }

    final leftLocalId = _nonEmptyString(left.localId);
    final rightLocalId = _nonEmptyString(right.localId);

    return leftLocalId != null && leftLocalId == rightLocalId;
  }

  String? _downloadLocalId(OfflineTrackDownload download) {
    return _nonEmptyString(download.localTrackId) ?? _nonEmptyString(download.track.localId);
  }

  String _serverTrackId(OfflineTrackDownload download) {
    return download.track.serverTrackId ?? download.track.id;
  }

  String _offlineDownloadKey(OfflineTrackDownload download) {
    return '${download.serverBaseUrl}\n${_serverTrackId(download)}';
  }

  String? _nonEmptyString(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  Future<void> _downloadTrackCollection(
    Iterable<Track> tracks, {
    required String label,
    required String emptyMessage,
    String kind = 'tracks',
    String? sourceId,
  }) async {
    if (!_host._requireServer('downloading $label')) {
      return;
    }

    final uniqueTracks = <String, Track>{};

    for (final track in tracks) {
      final id = track.id.trim();

      if (id.isEmpty) {
        continue;
      }

      uniqueTracks[id] = track;
    }

    if (uniqueTracks.isEmpty) {
      _host._pushMessage(emptyMessage);

      return;
    }

    final pending = uniqueTracks.values.where((track) => !_downloadQueuedOrAvailable(track)).toList(growable: false);

    if (pending.isEmpty) {
      _host._pushMessage('All tracks are already downloaded or queued for $label.');

      return;
    }

    try {
      final queuedCount = await _host._offlineDownloadManager.queueTracks(
        pending,
        label: label,
        kind: kind,
        sourceId: sourceId,
      );

      if (queuedCount == 0) {
        _host._pushMessage('All tracks are already downloaded or queued for $label.');

        return;
      }

      final queuedTrackLabel = queuedCount == 1 ? 'track' : 'tracks';

      _host._pushMessage('Queued $queuedCount $queuedTrackLabel for $label.');
    } catch (err) {
      _host._pushMessage('Failed to queue downloads for $label: $err', level: LogLevel.warning);
    }
  }

  bool _downloadQueuedOrAvailable(Track track) {
    final download = _host.offlineDownloadForTrack(track.id);
    if (download == null) {
      return false;
    }

    if (download.status == OfflineDownloadStatus.queued ||
        download.status == OfflineDownloadStatus.preparing ||
        download.status == OfflineDownloadStatus.downloading ||
        download.status == OfflineDownloadStatus.validating ||
        download.status == OfflineDownloadStatus.removing) {
      return true;
    }

    return _host.availableOfflineDownloadForTrack(track.id) != null;
  }

  bool _offlineDownloadPausable(OfflineDownloadStatus status) {
    return status == OfflineDownloadStatus.queued ||
        status == OfflineDownloadStatus.preparing ||
        status == OfflineDownloadStatus.downloading ||
        status == OfflineDownloadStatus.validating;
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DownloadFacade {
  _DownloadCoordinator get _downloadsCoordinator;

  List<OfflineTrackDownload> get availableOfflineDownloads => _downloadsCoordinator.availableOfflineDownloads;

  OfflineTrackDownload? offlineDownloadForTrack(String trackId) =>
      _downloadsCoordinator.offlineDownloadForTrack(trackId);

  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) =>
      _downloadsCoordinator.availableOfflineDownloadForTrack(trackId);

  Track? serverTrackForCurrentServer(Track track) => _downloadsCoordinator.serverTrackForCurrentServer(track);

  Future<void> downloadTrack(Track track) => _downloadsCoordinator.downloadTrack(track);

  Future<void> downloadAlbum(Album album, List<Track> tracks) => _downloadsCoordinator.downloadAlbum(album, tracks);

  Future<void> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _downloadsCoordinator.downloadPlaylist(
    playlist,
    tracks,
    name: name,
    description: description,
    imageEdit: imageEdit,
  );

  Future<void> downloadArtist(Artist artist, List<Album> albums) =>
      _downloadsCoordinator.downloadArtist(artist, albums);

  Future<void> removeOfflineTrack(String trackId) => _downloadsCoordinator.removeOfflineTrack(trackId);

  Future<void> pauseOfflineDownload(OfflineTrackDownload download) =>
      _downloadsCoordinator.pauseOfflineDownload(download);

  Future<void> resumeOfflineDownload(OfflineTrackDownload download) =>
      _downloadsCoordinator.resumeOfflineDownload(download);

  Future<void> pauseOfflineDownloadJob(OfflineDownloadJob job) => _downloadsCoordinator.pauseOfflineDownloadJob(job);

  Future<void> resumeOfflineDownloadJob(OfflineDownloadJob job) => _downloadsCoordinator.resumeOfflineDownloadJob(job);

  Future<void> pauseAllOfflineDownloads() => _downloadsCoordinator.pauseAllOfflineDownloads();

  Future<void> retryOfflineDownload(OfflineTrackDownload download) =>
      _downloadsCoordinator.retryOfflineDownload(download);

  Future<void> cancelOfflineDownload(OfflineTrackDownload download) =>
      _downloadsCoordinator.cancelOfflineDownload(download);

  Future<void> cancelOfflineDownloadJob(OfflineDownloadJob job) => _downloadsCoordinator.cancelOfflineDownloadJob(job);

  Future<void> removeOfflineDownload(OfflineTrackDownload download) =>
      _downloadsCoordinator.removeOfflineDownload(download);

  Future<void> removeOfflineDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) => _downloadsCoordinator.removeOfflineDownloads(downloads, label: label, scope: scope);

  Future<void> removeDownloadedTrack(Track track) => _downloadsCoordinator.removeDownloadedTrack(track);

  Future<void> removeDownloadedTracks(
    Iterable<Track> tracks, {
    String? label,
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) => _downloadsCoordinator.removeDownloadedTracks(tracks, label: label, scope: scope);

  Future<void> clearFailedOfflineDownloads() => _downloadsCoordinator.clearFailedOfflineDownloads();

  Future<void> resumePausedOfflineDownloads() => _downloadsCoordinator.resumePausedOfflineDownloads();

  Future<void> clearUnfinishedOfflineDownloads() => _downloadsCoordinator.clearUnfinishedOfflineDownloads();

  bool _sameTrackIdentity(Track left, Track right) => _downloadsCoordinator._sameTrackIdentity(left, right);
}
