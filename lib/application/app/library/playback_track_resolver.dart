part of 'package:phonolite_app/application/app/app_controller.dart';

class _PlaybackTrackResolver {
  final AppController _host;
  final Map<String, String> _albumIdByKey = <String, String>{};
  int _albumIdCacheSessionRevision = -1;
  int _metadataReadRevision = 0;

  _PlaybackTrackResolver(this._host);

  Future<Track> _hydrateTrackForPlayback(Track track) async {
    final sessionRevision = _host.connection.sessionRevision;
    final metadataRevision = _metadataReadRevision;
    Track full = track;

    try {
      full = await _host.connection.fetchTrackById(track.id);
      _host._pushMessage(
        'Track details response: id=${full.id} artist="${full.artist}" album="${full.album}" albumId="${full.albumId ?? ''}"',
      );
    } catch (err) {
      _host._pushMessage('Track details lookup failed: $err');
    }

    if (_host.connection.sessionRevision != sessionRevision || metadataRevision != _metadataReadRevision) {
      return track;
    }

    var resolvedAlbumId = full.albumId ?? track.albumId;

    if ((resolvedAlbumId == null || resolvedAlbumId.isEmpty) && full.artist.isNotEmpty && full.album.isNotEmpty) {
      final key = _albumKey(full.artist, full.album);

      resolvedAlbumId = _albumIdByKey[key];

      if (resolvedAlbumId == '') {
        return full;
      }

      if (resolvedAlbumId == null || resolvedAlbumId.isEmpty) {
        resolvedAlbumId = await _resolveAlbumIdBySearch(artist: full.artist, album: full.album);

        if (_host.connection.sessionRevision != sessionRevision || metadataRevision != _metadataReadRevision) {
          return track;
        }

        if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
          _rememberAlbumId(key, resolvedAlbumId);
        }
      }

      if (resolvedAlbumId != null && resolvedAlbumId.isNotEmpty) {
        full = full.copyWith(albumId: resolvedAlbumId);
      }
    }

    if ((full.artist.isEmpty || full.album.isEmpty || resolvedAlbumId == null || resolvedAlbumId.isEmpty) &&
        resolvedAlbumId != null &&
        resolvedAlbumId.isNotEmpty) {
      try {
        final album = await _host.connection.fetchAlbumById(resolvedAlbumId);

        full = _mergeTrackWithAlbum(full, album);

        if (full.artist.isEmpty && album.artistId.isNotEmpty) {
          final artist = await _host.connection.fetchArtistById(album.artistId);

          full = _mergeTrackWithArtist(full, artist);
        }
      } catch (err) {
        _host._pushMessage('Album/artist lookup failed: $err');
      }
    }

    if (full.albumId == null || full.albumId!.isEmpty) {
      final albumId = resolvedAlbumId;

      if (albumId != null && albumId.isNotEmpty) {
        full = full.copyWith(albumId: albumId);
      }
    }

    return full;
  }

  bool _needsTrackHydration(Track track) {
    return track.artist.isEmpty || track.album.isEmpty || track.albumId == null || track.albumId!.isEmpty;
  }

  String _albumKey(String artist, String album) {
    if (_albumIdCacheSessionRevision != _host.connection.sessionRevision) {
      _albumIdByKey.clear();
      _albumIdCacheSessionRevision = _host.connection.sessionRevision;
    }

    return '${artist.trim().toLowerCase()}|${album.trim().toLowerCase()}';
  }

  void _cacheAlbumId({required Album album}) {
    final key = _albumKey(album.artist, album.title);

    if (key == '|' || album.id.isEmpty) {
      return;
    }

    _rememberAlbumId(key, album.id);
  }

  void _cacheTrackAlbumId(Track track, {String? fallbackAlbumId}) {
    final albumId = track.albumId ?? fallbackAlbumId;

    if (albumId == null || albumId.isEmpty) {
      return;
    }

    final key = _albumKey(track.artist, track.album);

    if (key == '|') {
      return;
    }

    _rememberAlbumId(key, albumId);
  }

  void _rememberAlbumId(String key, String albumId) {
    final previous = _albumIdByKey[key];

    // An empty entry marks multiple releases sharing the same artist and title.
    _albumIdByKey[key] = previous == null || previous == albumId ? albumId : '';
  }

  String _normalizeLookup(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String?> _resolveAlbumIdBySearch({required String artist, required String album}) async {
    final normalizedAlbum = _normalizeLookup(album);

    if (normalizedAlbum.isEmpty) {
      return null;
    }

    final normalizedArtist = _normalizeLookup(artist);

    if (normalizedArtist.isEmpty) {
      return null;
    }

    final query = [artist, album].where((part) => part.trim().isNotEmpty).join(' ');

    if (query.isEmpty) {
      return null;
    }

    try {
      final results = await _host.connection.search(query, filter: 'album');

      if (results.isEmpty) {
        return null;
      }

      final matches = <String>{};

      for (final result in results) {
        if (result.kind != 'album' || result.id.isEmpty) {
          continue;
        }

        final title = _normalizeLookup(result.title);

        if (title != normalizedAlbum) {
          continue;
        }

        final subtitle = _normalizeLookup(result.subtitle ?? '');

        if (subtitle == normalizedArtist) {
          matches.add(result.id);
        }
      }

      // A shared title or a partial artist name cannot identify a recording.
      // Multiple exact releases remain ambiguous without an explicit album ID.
      if (matches.length == 1) {
        return matches.single;
      }
    } catch (err) {
      _host._pushMessage('Album search fallback failed: $err');
    }

    return null;
  }

  List<Track> _normalizeQueueTracks(List<Track> tracks) {
    Track resolveAlbumIdentity(Track track) {
      if (track.albumId != null && track.albumId!.isNotEmpty) {
        return track;
      }

      final key = _albumKey(track.artist, track.album);
      final albumId = _albumIdByKey[key];

      if (albumId == null || albumId.isEmpty) {
        return track;
      }

      return track.copyWith(albumId: albumId);
    }

    return tracks.map(resolveAlbumIdentity).toList();
  }

  Track _mergeTrackWithAlbum(Track track, Album album) {
    final albumTitle = track.album.isNotEmpty ? track.album : album.title;
    final artistName = track.artist.isNotEmpty ? track.artist : album.artist;

    return track.copyWith(artist: artistName, album: albumTitle, albumId: track.albumId ?? album.id);
  }

  Track _mergeTrackWithArtist(Track track, Artist artist) {
    final artistName = track.artist.isNotEmpty ? track.artist : artist.name;

    return track.copyWith(artist: artistName);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _PlaybackTrackResolverFacade {
  _PlaybackTrackResolver get _resolverCoordinator;

  Map<String, String> get _albumIdByKey => _resolverCoordinator._albumIdByKey;

  int get _metadataReadRevision => _resolverCoordinator._metadataReadRevision;

  set _metadataReadRevision(int value) => _resolverCoordinator._metadataReadRevision = value;

  Future<Track> _hydrateTrackForPlayback(Track track) => _resolverCoordinator._hydrateTrackForPlayback(track);

  bool _needsTrackHydration(Track track) => _resolverCoordinator._needsTrackHydration(track);

  void _cacheAlbumId({required Album album}) => _resolverCoordinator._cacheAlbumId(album: album);

  void _cacheTrackAlbumId(Track track, {String? fallbackAlbumId}) =>
      _resolverCoordinator._cacheTrackAlbumId(track, fallbackAlbumId: fallbackAlbumId);

  List<Track> _normalizeQueueTracks(List<Track> tracks) => _resolverCoordinator._normalizeQueueTracks(tracks);
}
