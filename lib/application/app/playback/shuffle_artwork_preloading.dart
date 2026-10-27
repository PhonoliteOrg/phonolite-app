part of '../app_controller.dart';

extension _ShuffleArtworkPreloading on _ShuffleCoordinator {
  static const int _artworkWindowSize = 3;

  void _preloadServerShuffleArtwork() {
    final preloader = _host._shuffleArtworkPreloader;
    final nativeArtwork = _host._nowPlayingPlatform.loadsArtworkNatively;

    if ((preloader == null && !nativeArtwork) || _serverDeck == null || _host._disposed) {
      return;
    }

    // Keep the selected cover and the next two tracks decoded. Derive the
    // window from the deck cursor: playback state may still name the old track.
    final sources = <String>{};
    final headers = _host.artworkHeaders;
    final requests = <ArtworkRequest>[];
    final nativeSources = <NativeArtworkSource>[];

    for (final track in _host._playQueue.skip(max(0, _host._playIndex)).take(_artworkWindowSize)) {
      final localPath = track.albumArtPath?.trim();
      final local = localPath != null && localPath.isNotEmpty;
      final albumId = track.albumId?.trim();
      final url = albumId == null || albumId.isEmpty ? null : _host.connection.buildAlbumCoverUrl(albumId);
      final source = local ? localPath : url;

      if (source != null && sources.add(source)) {
        requests.add(ArtworkRequest(source: source, headers: local ? const {} : headers));
      }

      // The native publisher uses the server cover for server playback, even
      // when Flutter can display a downloaded local copy of that cover.
      final useLocal = !_host._canAttemptRemotePlayback && local;
      final key = NowPlayingArtwork.sourceKey(url: useLocal ? null : url, localPath: useLocal ? localPath : null);

      if (key != null) {
        nativeSources.add(
          NativeArtworkSource(
            key: key,
            url: useLocal ? null : url,
            path: useLocal ? localPath : null,
            token: useLocal ? null : _host.connection.token,
            serverPin: useLocal ? null : _host.connection.trust?.spki,
          ),
        );
      }
    }

    preloader?.update(requests);
    _preloadNativeArtwork(nativeSources);
  }

  void _preloadNativeArtwork(List<NativeArtworkSource> sources) {
    if (!_host._nowPlayingPlatform.loadsArtworkNatively) {
      return;
    }

    unawaited(
      _host._nowPlayingPlatform
          .preloadArtwork(sources)
          .catchError((Object error) => AppLogger.debug('Native artwork preload skipped: $error')),
    );
  }
}
