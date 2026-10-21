import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/library_destination.dart';
import 'package:phonolite_app/data/models/library/local_library_selection.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';

export 'package:phonolite_app/data/models/library/library_destination.dart';

class LibraryNavigationController extends FeatureController {
  final AppController app;
  late final _requests = createRequestGeneration();

  LibraryNavigationController(this.app);

  void cancelPending() => _requests.advance();

  LocalLibrarySelection localSelection({bool accountOnly = false}) {
    final snapshot = app.offlineLibrarySnapshot;

    if (!accountOnly || !app.authState.hasSession) {
      return LocalLibrarySelection(tracks: snapshot.tracks, artists: snapshot.artistGroups);
    }

    final tracks = snapshot.tracks.where((track) => track.serverBaseUrl == app.catalog.baseUrl).toList();

    return LocalLibrarySelection(tracks: tracks, artists: offlineArtistGroups(tracks));
  }

  Future<LibraryDestination?> search(SearchResult result, {required bool local}) async {
    final revision = app.catalog.sessionRevision;
    final generation = _requests.current;

    if (local) {
      final selection = localSelection();

      if (result.kind == 'artist') {
        final artist = selection.artist(result.id);

        return artist == null ? null : LibraryDestination(localArtist: artist);
      }

      final track = result.kind == 'track' ? selection.track(result.id) : null;
      final OfflineAlbumGroup? album;

      if (result.kind == 'album') {
        album = selection.album(result.id);
      } else if (track != null) {
        album = selection.albumForTrack(track);
      } else {
        album = null;
      }

      if (album == null) {
        return null;
      }

      if (track != null) {
        await app.playOfflineTrack(track.id, tracks: album.tracks);
      }

      return _current(revision, generation)
          ? LibraryDestination(localArtist: selection.artist(album.artistId), localAlbum: album)
          : null;
    }

    try {
      if (result.kind == 'artist') {
        final artist = await app.catalog.fetchArtistById(result.id);

        return _current(revision, generation) ? LibraryDestination(artist: artist) : null;
      }

      Track? track;
      String? albumId;

      if (result.kind == 'album') {
        albumId = result.id;
      } else if (result.kind == 'track') {
        track = await app.catalog.fetchTrackById(result.id);
        albumId = track.albumId;
      }

      if (albumId == null || albumId.isEmpty || !_current(revision, generation)) {
        return null;
      }

      final album = await app.catalog.fetchAlbumById(albumId);

      if (!_current(revision, generation)) {
        return null;
      }

      final artist = await app.catalog.fetchArtistById(album.artistId);

      if (!_current(revision, generation)) {
        return null;
      }

      if (track != null) {
        await app.loadTracks(album.id);

        if (!_current(revision, generation)) {
          return null;
        }

        await app.queueAlbum(album.id, startTrackId: track.id);
      }

      return _current(revision, generation)
          ? LibraryDestination(
              artist: artist,
              album: album,
              artistName: album.artist.isNotEmpty ? album.artist : track?.artist ?? '',
            )
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<LibraryDestination?> track(Track track, {required bool local, LocalLibrarySelection? selection}) async {
    if (local) {
      final library = selection ?? localSelection();
      final album = library.albumForTrack(track);
      if (album == null) {
        return null;
      }

      final artist = library.artist(album.artistId) ?? library.artistForTrack(track);

      return artist == null ? null : LibraryDestination(localArtist: artist, localAlbum: album);
    }

    final id = track.albumId;

    if (id == null || id.isEmpty || !app.authState.isAuthorized) {
      return null;
    }

    final revision = app.catalog.sessionRevision;
    final generation = _requests.current;
    final album = await app.catalog.fetchAlbumById(id);

    if (!_current(revision, generation) || !app.authState.isAuthorized) {
      return null;
    }

    final name = album.artist.isNotEmpty ? album.artist : track.artist;

    return LibraryDestination(
      artist: Artist(id: album.artistId, name: name, albumCount: 0),
      album: album,
      artistName: name,
    );
  }

  Future<LibraryDestination?> statsArtist(StatsItem item) async {
    final revision = app.catalog.sessionRevision;
    final generation = _requests.current;

    if (app.authState.isAuthorized) {
      try {
        final artist = await app.catalog.fetchArtistById(item.id);

        if (!_current(revision, generation)) {
          return null;
        }

        if (app.authState.isAuthorized) {
          return LibraryDestination(artist: artist);
        }
      } catch (_) {}
    }

    if (!_current(revision, generation)) {
      return null;
    }

    final selection = localSelection(accountOnly: true);
    final artist =
        selection.artist(item.id) ?? (item.id == item.name ? selection.artist(item.name.trim().toLowerCase()) : null);

    return artist == null ? null : LibraryDestination(localArtist: artist);
  }

  Future<LibraryDestination?> statsTrack(StatsTrack item) async {
    final revision = app.catalog.sessionRevision;
    final generation = _requests.current;

    if (app.authState.isAuthorized) {
      try {
        final value = await app.catalog.fetchTrackById(item.id);

        if (!_current(revision, generation)) {
          return null;
        }

        final destination = await track(value, local: false);
        if (destination != null) {
          return destination;
        }
      } catch (_) {}
    }

    if (!_current(revision, generation)) {
      return null;
    }

    final selection = localSelection(accountOnly: true);
    final value = selection.track(item.id);

    return value == null ? null : track(value, local: true, selection: selection);
  }

  bool _current(int revision, int generation) =>
      _requests.isCurrent(generation) && app.catalog.sessionRevision == revision;
}
