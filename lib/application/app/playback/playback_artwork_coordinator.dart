part of '../app_controller.dart';

/// Warms optional covers independently of the audio source and Flutter rendering.
class _PlaybackArtworkCoordinator {
  final AppController _host;

  _PlaybackArtworkCoordinator(this._host);

  void warm(Track track, {required bool local, required bool Function() isCurrent}) {
    unawaited(_warm(track, local: local, isCurrent: isCurrent));
  }

  Future<void> _warm(Track track, {required bool local, required bool Function() isCurrent}) async {
    final preloader = _host._shuffleArtworkPreloader;
    if (preloader == null || !isCurrent()) {
      return;
    }

    try {
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

      if (!isCurrent() || metadataRevision != _host._metadataReadRevision) {
        return;
      }

      _host._playQueue = _host._playQueue
          .map(
            (item) =>
                item.id == resolved.id ? resolved.copyWith(liked: item.liked, inPlaylists: item.inPlaylists) : item,
          )
          .toList();
      final current = _host._playbackState.track;
      if (current?.id == resolved.id) {
        _host._updatePlayback(
          track: resolved.copyWith(liked: current!.liked, inPlaylists: current.inPlaylists),
        );
      }
      final request = _coverRequest(resolved, local: local);
      if (request == null) {
        return;
      }

      await preloader.prepare(request);
    } catch (error) {
      if (isCurrent()) {
        _host._pushMessage('Playback artwork unavailable: $error', level: LogLevel.debug);
      }
    }
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
