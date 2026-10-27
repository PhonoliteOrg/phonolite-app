part of '../app_controller.dart';

extension _ShuffleArtworkPreloading on _ShuffleCoordinator {
  static const int _artworkWindowSize = 3;

  void _preloadServerShuffleArtwork() {
    final preloader = _host._shuffleArtworkPreloader;
    if (preloader == null || _serverDeck == null || _host._disposed) return;

    // Keep the selected cover and the next two tracks decoded. Derive the
    // window from the deck cursor: playback state may still name the old track.
    final sources = <String>{};
    final headers = _host.artworkHeaders;
    final requests = <ArtworkRequest>[];
    for (final track in _host._playQueue.skip(max(0, _host._playIndex)).take(_artworkWindowSize)) {
      final localPath = track.albumArtPath?.trim();
      final local = localPath != null && localPath.isNotEmpty;
      final albumId = track.albumId?.trim();
      final source = local
          ? localPath
          : albumId == null || albumId.isEmpty
          ? null
          : _host.connection.buildAlbumCoverUrl(albumId);
      if (source == null || !sources.add(source)) continue;

      requests.add(ArtworkRequest(source: source, headers: local ? const {} : headers));
    }
    preloader.update(requests);
  }
}
