part of '../app_controller.dart';

/// Resolves playlist identities without assigning another server's IDs to them.
class _PlaylistSourceCoordinator {
  final AppController _host;
  final Map<SourceTrackRef, String> _localIds = {};
  late final TrackSourceResolver _resolver = TrackSourceResolver(
    connection: _host.connection,
    readMatches: _host._offlineDownloadManager.readServerTrackMatches,
    saveMatch: _host._offlineDownloadManager.saveTrackSourceMatch,
    removeMatch: _host._offlineDownloadManager.removeTrackSourceMatch,
  );

  _PlaylistSourceCoordinator(this._host);

  SourceTrackRef? sourceForTrack(Track track) {
    if (track.localId != null && track.serverTrackId == null) {
      return null;
    }

    final source = SourceTrackRef.fromTrack(track, fallbackServerBaseUrl: _host.connection.baseUrl);

    return source.isValid ? source : null;
  }

  Future<String?> resolveLocalTrackId(Track track) async {
    final source = sourceForTrack(track);
    final captured = source == null
        ? track
        : track.copyWith(serverBaseUrl: source.serverBaseUrl, serverTrackId: source.serverTrackId);
    final id = await _host._offlineDownloadManager.resolveLocalPlaylistTrackId(captured);

    if (source != null) {
      if (id == null) {
        _localIds.remove(source);
      } else {
        _localIds[source] = id;
      }
    }

    return id;
  }

  Future<Track?> resolveServerTrack(Track track) async {
    if (!_host.authState.isAuthorized) {
      return null;
    }

    return _resolver.resolveServerTrack(track, downloads: _host._offlineDownloadManager.downloads);
  }

  bool contains(Playlist playlist, Track track) {
    final source = sourceForTrack(track);

    if (source != null && playlist.pendingTrackSources.contains(source)) {
      return true;
    }

    final known = source == null
        ? null
        : _host._offlineDownloadManager.find(source.serverBaseUrl, source.serverTrackId);
    final localId = track.localId ?? known?.localTrackId ?? (source == null ? null : _localIds[source]);

    return localId != null && playlist.trackIds.contains(localId);
  }

  OfflineTrackDownload? downloadForEntry(LocalPlaylistEntry entry) {
    final source = entry.source;

    if (source != null) {
      return _host._offlineDownloadManager.find(source.serverBaseUrl, source.serverTrackId);
    }

    final localId = entry.localTrackId;

    return localId == null ? null : _host._offlineDownloadManager.findLocal(localId);
  }
}
