part of '../offline_download_client.dart';

class _ArtistJobDiscovery {
  final _OfflineDownloadActorCore _host;

  _ArtistJobDiscovery(this._host);

  Future<void> _discoverArtistJobItems(OfflineDownloadJob job, {required int targetUnmaterialized}) async {
    if (_host.connection.token == null || _host.connection.token!.isEmpty) {
      return;
    }

    var items = List<OfflineDownloadJobItem>.from(
      _host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[],
    );

    int unmaterializedCount() =>
        items.where((item) => !item.materialized && item.status == OfflineDownloadStatus.queued).length;

    if (unmaterializedCount() >= targetUnmaterialized) {
      return;
    }

    final sources = List<OfflineDownloadJobSource>.from(
      _host._jobSourcesByJobId[job.jobId] ?? const <OfflineDownloadJobSource>[],
    );
    final seen = {for (final item in items) item.serverTrackId};
    final discoveredItems = <OfflineDownloadJobItem>[];
    final discoveredSources = <OfflineDownloadJobSource>[];
    var nextPosition = items.isEmpty ? 0 : items.map((item) => item.position).reduce((a, b) => a > b ? a : b) + 1;
    var changed = false;
    final now = DateTime.now();

    for (var i = 0; i < sources.length; i += 1) {
      if (_host.connection.baseUrl != job.serverBaseUrl ||
          _host.connection.token == null ||
          _host.connection.token!.isEmpty ||
          _host._pausedServerUrls.contains(job.serverBaseUrl)) {
        break;
      }

      if (unmaterializedCount() >= targetUnmaterialized) {
        break;
      }

      final source = sources[i];

      if (source.status != OfflineDownloadStatus.queued) {
        continue;
      }

      try {
        final tracks = await _host.connection.fetchTracks(source.sourceId);

        if (_host._disposed || _host._jobById(job.jobId) == null) {
          return;
        }

        for (final rawTrack in tracks) {
          final id = rawTrack.id.trim();

          if (id.isEmpty || !seen.add(id)) {
            continue;
          }

          await _host._ownerPlaylistDownloads.registerDemand(
            SourceTrackRef(serverBaseUrl: job.serverBaseUrl, serverTrackId: id),
            ownerKind: 'collection',
            ownerId: job.jobId,
          );

          final existing = _host.find(job.serverBaseUrl, id);

          if (existing != null) {
            if (_host._downloadAvailable(existing)) {
              discoveredItems.add(
                OfflineDownloadJobItem(
                  jobId: job.jobId,
                  position: nextPosition,
                  serverTrackId: id,
                  status: OfflineDownloadStatus.downloaded,
                  materialized: true,
                  createdAt: now,
                  updatedAt: now,
                  track: existing.track,
                  offlineMetadata: existing.offlineMetadata,
                ),
              );
              nextPosition += 1;
              changed = true;
            }

            if (_host._downloadQueuedOrAvailable(existing)) {
              continue;
            }

            discoveredItems.add(
              OfflineDownloadJobItem(
                jobId: job.jobId,
                position: nextPosition,
                serverTrackId: id,
                status: OfflineDownloadStatus.queued,
                materialized: false,
                createdAt: now,
                updatedAt: now,
                track: rawTrack.copyWith(id: id, serverBaseUrl: job.serverBaseUrl, serverTrackId: id),
                offlineMetadata: existing.offlineMetadata,
              ),
            );
            nextPosition += 1;
            changed = true;
            continue;
          }

          discoveredItems.add(
            OfflineDownloadJobItem(
              jobId: job.jobId,
              position: nextPosition,
              serverTrackId: id,
              status: OfflineDownloadStatus.queued,
              materialized: false,
              createdAt: now,
              updatedAt: now,
              track: rawTrack.copyWith(id: id, serverBaseUrl: job.serverBaseUrl, serverTrackId: id),
            ),
          );
          nextPosition += 1;
          changed = true;
        }

        sources[i] = source.copyWith(status: OfflineDownloadStatus.downloaded, updatedAt: now, error: null);
      } catch (err) {
        AppLogger.warning(
          'Could not discover album ${source.label ?? source.sourceId} for '
          '${job.label ?? job.jobId}; download request retained: $err',
        );
        sources[i] = source.copyWith(status: OfflineDownloadStatus.failed, updatedAt: now, error: err.toString());
      }

      discoveredSources.add(sources[i]);
      items = [..._host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[], ...discoveredItems];
      changed = true;
    }

    if (!changed) {
      return;
    }

    if (_host._disposed || _host._jobById(job.jobId) == null) {
      return;
    }

    // Existing items can finish while an album lookup is in flight. Persist
    // only discoveries so an old snapshot cannot undo their progress.
    await _host._storage.saveDownloadJobDiscovery(items: discoveredItems, sources: discoveredSources);

    _host._jobItemsByJobId[job.jobId] = [
      ..._host._jobItemsByJobId[job.jobId] ?? const <OfflineDownloadJobItem>[],
      ...discoveredItems,
    ];

    final sourcesById = {for (final source in discoveredSources) source.sourceId: source};

    _host._jobSourcesByJobId[job.jobId] = [
      for (final source in _host._jobSourcesByJobId[job.jobId] ?? sources) sourcesById[source.sourceId] ?? source,
    ];

    await _host._refreshJobCounts(job.jobId);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _ArtistJobDiscoveryFacade {
  _ArtistJobDiscovery get _ownerDiscovery;

  Future<void> _discoverArtistJobItems(OfflineDownloadJob job, {required int targetUnmaterialized}) =>
      _ownerDiscovery._discoverArtistJobItems(job, targetUnmaterialized: targetUnmaterialized);
}
