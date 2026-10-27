part of '../offline_download_client.dart';

/// Owns saved playlist requests independently of the lifetime of their modal.
class _LocalPlaylistDownloads {
  final _OfflineDownloadActorCore _host;
  final Map<String, Future<void>> _staging = {};
  final Map<String, int> _generations = {};
  final Map<String, int> _stagingSessions = {};
  final Set<String> _reschedule = {};
  Future<void> _mutations = Future<void>.value();

  _LocalPlaylistDownloads(this._host);

  Future<void> get mutationsDrained => _mutations;

  Future<void> dispose() async {
    await _mutations;
    await Future.wait(_staging.values.toList());
  }

  Future<T> mutate<T>(Future<T> Function() operation) {
    Future<T> run(void _) {
      if (_host._disposed || _host._resettingLocalData) {
        throw StateError('Local playlist operation canceled by shutdown or reset.');
      }

      return operation();
    }

    final result = _mutations.then(run);

    // The returned result retains failures; a failed command must not block later commands.
    _mutations = result.then<void>((_) {}, onError: (Object error, StackTrace trace) {});

    return result;
  }

  Future<void> registerDemand(SourceTrackRef source, {required String ownerKind, required String ownerId}) =>
      mutate(() => _host._storage.registerDownloadDemand(source, ownerKind: ownerKind, ownerId: ownerId));

  Future<void> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) =>
      mutate(() => _saveSourceToLocalPlaylist(playlistId, track, source));

  Future<void> _saveSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) async {
    await _host._ensureLoaded();

    final revision = _host._localDataRevision;

    final saved = await _host._storage.addSourceToLocalPlaylist(playlistId, track, source);

    if (!_host._localDataCurrent(revision)) {
      throw StateError('Playlist addition canceled by local data reset.');
    }

    await _host._loadLocalUserData();

    if (saved.isPending && saved.source != null) {
      _scheduleSource(saved.source!, retry: true);
    }
  }

  Future<String?> resolveLocalPlaylistTrackId(Track track) async {
    await _host._ensureLoaded();

    if (track.localId case final String localId when localId.isNotEmpty) {
      return localId;
    }

    final source = SourceTrackRef.fromTrack(track, fallbackServerBaseUrl: _host.connection.baseUrl);

    return _host._storage.resolveDownloadedLocalSource(track, source);
  }

  Future<void> retryLocalPlaylistEntry(LocalPlaylistEntry entry) => mutate(() => _saveRetry(entry));

  Future<void> _saveRetry(LocalPlaylistEntry entry) async {
    final revision = _host._localDataRevision;
    final source = entry.source;

    if (source == null) {
      return;
    }

    final entries = await _host._storage.readLocalPlaylistEntries(entry.playlistId);
    final current = entries
        .where((candidate) => candidate.entryKey == entry.entryKey && candidate.source == source)
        .firstOrNull;

    if (current == null || current.isPlayable) {
      return;
    }

    await _host._storage.registerDownloadDemand(source, ownerKind: 'playlist', ownerId: entry.entryKey);

    if (!_host._localDataCurrent(revision)) {
      throw StateError('Playlist retry canceled by local data reset.');
    }

    await _host._storage.updatePendingPlaylistRequest(source, OfflineDownloadStatus.queued);
    await _host._loadLocalUserData();

    _scheduleSource(source, retry: true);
  }

  Future<void> resumeLocalPlaylistEntry(LocalPlaylistEntry entry) => retryLocalPlaylistEntry(entry);

  Future<void> _resumePendingPlaylistDownloads() async {
    if (_host._disposed || _host._resettingLocalData) {
      return;
    }

    final entries = await _host._storage.readPendingPlaylistEntries(serverBaseUrl: _host.connection.baseUrl);

    for (final entry in entries) {
      if (entry.source case final source? when entry.status == OfflineDownloadStatus.queued) {
        _scheduleSource(source);
      }
    }
  }

  void _scheduleSource(SourceTrackRef source, {bool retry = false}) {
    if (_host._disposed || _host._resettingLocalData) {
      return;
    }

    if (_staging.containsKey(source.key)) {
      if (retry || _stagingSessions[source.key] != _host.connection.sessionRevision) {
        _reschedule.add(source.key);
      }

      return;
    }

    final generation = _generations[source.key] ?? 0;
    final dataRevision = _host._localDataRevision;
    _stagingSessions[source.key] = _host.connection.sessionRevision;

    bool isCurrent() => _host._localDataCurrent(dataRevision) && (_generations[source.key] ?? 0) == generation;

    Future<void> stage() async {
      final sessionRevision = _host.connection.sessionRevision;

      bool sameSession() =>
          source.serverBaseUrl == _host.connection.baseUrl && _host.connection.sessionRevision == sessionRevision;

      try {
        if (!isCurrent() || !await _host._storage.hasDownloadDemand(source)) {
          return;
        }

        if (source.serverBaseUrl != _host.connection.baseUrl ||
            _host.connection.token == null ||
            _host.connection.token!.isEmpty) {
          await _host._storage.updatePendingPlaylistRequest(source, OfflineDownloadStatus.paused);

          return;
        }

        final existing = _host.find(source.serverBaseUrl, source.serverTrackId);

        if (existing != null) {
          if (existing.isDownloaded) {
            await _host._storage.upsertDownload(existing);
          } else if (retry) {
            await _host.resumeDownload(existing);
          }

          return;
        }

        final entries = await _host._storage.readPendingPlaylistEntries(serverBaseUrl: source.serverBaseUrl);
        final entry = entries.where((entry) => entry.source == source).firstOrNull;

        if (entry == null || !isCurrent()) {
          return;
        }

        if (!sameSession()) {
          await _host._storage.updatePendingPlaylistRequest(source, OfflineDownloadStatus.paused);

          return;
        }

        await _host._ownerPlanning.downloadTrack(
          entry.track.copyWith(
            id: source.serverTrackId,
            serverBaseUrl: source.serverBaseUrl,
            serverTrackId: source.serverTrackId,
          ),
          playlistOwned: true,
          isCurrent: isCurrent,
        );
      } catch (error) {
        if (isCurrent()) {
          await _host._storage.updatePendingPlaylistRequest(
            source,
            sameSession() ? OfflineDownloadStatus.failed : OfflineDownloadStatus.paused,
            error: sameSession() ? '$error' : null,
          );
        }
      } finally {
        if (!isCurrent() && !_host._disposed && !_host._resettingLocalData) {
          await mutate(() => _cleanupUnclaimedPlaylistDownload(source));
        }

        if (isCurrent()) {
          try {
            if (!sameSession()) {
              await _host._storage.updatePendingPlaylistRequest(source, OfflineDownloadStatus.paused);
            }

            await _host._loadLocalUserData();
          } catch (error) {
            AppLogger.warning('Failed to refresh saved playlist downloads: $error');
          }
        }
      }
    }

    void reportFailure(Object error, StackTrace trace) {
      AppLogger.warning('Saved playlist download staging failed: $error');
    }

    late final Future<void> completion;

    void finishStaging() {
      if (identical(_staging[source.key], completion)) {
        _staging.remove(source.key);
        _stagingSessions.remove(source.key);
      }

      final requested = _reschedule.remove(source.key);

      if ((requested || !isCurrent()) && !_host._disposed && !_host._resettingLocalData) {
        _scheduleSource(source, retry: requested);
      }
    }

    completion = Future<void>(stage).catchError(reportFailure).whenComplete(finishStaging);
    _staging[source.key] = completion;
  }

  Future<void> _cleanupUnclaimedPlaylistDownload(SourceTrackRef source) async {
    if (await _host._storage.hasDownloadDemand(source)) {
      return;
    }

    _generations[source.key] = (_generations[source.key] ?? 0) + 1;

    final download = _host.find(source.serverBaseUrl, source.serverTrackId);

    if (download == null || download.isDownloaded) {
      return;
    }

    await _host._ownerDeletion.removeDownloads([download], unfinishedUnclaimedOnly: true);

    if (download.batchId case final String batchId) {
      await _host._ownerPlanning._discardEmptyPlaylistBatch(batchId);
    }
  }
}

mixin _LocalPlaylistDownloadsFacade {
  _LocalPlaylistDownloads get _ownerPlaylistDownloads;

  Future<void> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) =>
      _ownerPlaylistDownloads.addSourceToLocalPlaylist(playlistId, track, source);

  Future<String?> resolveLocalPlaylistTrackId(Track track) =>
      _ownerPlaylistDownloads.resolveLocalPlaylistTrackId(track);

  Future<void> retryLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _ownerPlaylistDownloads.retryLocalPlaylistEntry(entry);

  Future<void> resumeLocalPlaylistEntry(LocalPlaylistEntry entry) =>
      _ownerPlaylistDownloads.resumeLocalPlaylistEntry(entry);

  Future<void> _resumePendingPlaylistDownloads() => _ownerPlaylistDownloads._resumePendingPlaylistDownloads();

  Future<void> _cleanupUnclaimedPlaylistDownload(SourceTrackRef source) =>
      _ownerPlaylistDownloads._cleanupUnclaimedPlaylistDownload(source);
}
