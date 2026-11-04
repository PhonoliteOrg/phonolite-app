part of '../app_controller.dart';

/// Resolves the selected cover and waits for the same decoded key used by the UI.
/// Missing artwork is optional; stale work cannot install track metadata.
class _PlaybackArtworkCoordinator {
  final AppController _host;

  _PlaybackArtworkCoordinator(this._host);

  Future<Track> prepare(Track track, {required bool local, required bool Function() isCurrent}) async {
    final preloader = _host._shuffleArtworkPreloader;
    if (preloader == null) {
      return track;
    }

    while (isCurrent()) {
      final metadataRevision = _host._metadataReadRevision;
      var resolved = track;
      if (!local && _host._needsTrackHydration(track)) {
        try {
          final full = await _host._hydrateTrackForPlayback(track);
          resolved = _host.connection.projectServerTrack(
            full.copyWith(liked: track.liked, inPlaylists: track.inPlaylists),
          );
        } catch (error) {
          _host._pushMessage('Playback cover lookup unavailable: $error', level: LogLevel.debug);
        }
      }

      if (!isCurrent()) {
        return track;
      }
      if (metadataRevision != _host._metadataReadRevision) {
        track = _latestTrack(track);
        continue;
      }

      final request = _coverRequest(resolved, local: local);
      if (request == null) {
        return resolved;
      }

      var result = ArtworkPreparation.unavailable;
      try {
        result = await preloader.prepare(request);
      } catch (error) {
        _host._pushMessage('Playback artwork unavailable: $error', level: LogLevel.debug);
      }
      if (!isCurrent()) {
        return track;
      }
      if (metadataRevision != _host._metadataReadRevision) {
        track = _latestTrack(track);
        continue;
      }
      if (result == ArtworkPreparation.cancelled) {
        track = resolved;
        continue;
      }

      return resolved;
    }

    return track;
  }

  Track _latestTrack(Track fallback) {
    final current = _host._playbackState.track;

    return current?.id == fallback.id
        ? current!
        : _host._playQueue.where((item) => item.id == fallback.id).firstOrNull ?? fallback;
  }

  ArtworkRequest? _coverRequest(Track track, {required bool local}) {
    final path = track.albumArtPath?.trim();
    if (path != null && path.isNotEmpty) {
      return ArtworkRequest(source: path);
    }

    final albumId = track.albumId?.trim();
    if (local || albumId == null || albumId.isEmpty) {
      return null;
    }

    return ArtworkRequest(source: _host.connection.buildAlbumCoverUrl(albumId), headers: _host.artworkHeaders);
  }
}
