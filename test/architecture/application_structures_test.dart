import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/favorites/liked_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/library/album_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/artist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_controller.dart';
import 'package:phonolite_app/application/controllers/library/local_album_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/local_artist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlists_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

class _Connection extends Fake implements ServerConnection {
  @override
  Future<Artist> fetchArtistById(String id) async => _artist;
}

class _App extends Fake implements AppController {
  @override
  final connection = _Connection();
  @override
  final authState = AuthState(isAuthorized: false, baseUrl: '');
  @override
  Stream<AuthState> get authStream => const Stream.empty();
  @override
  Stream<Album> watchAlbum(String id) => const Stream.empty();
  @override
  Stream<Artist> watchArtist(String id) => const Stream.empty();
  @override
  Future<void> loadTracks(String albumId) async {}
  @override
  Future<void> loadArtistReleases(String artistId) async {}
  @override
  Future<void> loadLocalLikedTracks() async {}
  @override
  Future<void> loadLocalPlaylists() async {}
  @override
  List<OfflineTrackDownload> offlineDownloads = [];

  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String id) =>
      id == _track.id ? _download : null;
}

class _ObservingController extends FeatureController {
  _ObservingController(Stream<int> first, Stream<int> second) {
    listenTo(first, (value) => update(() => total += value));
    listenTo(second, (value) => update(() => total += value));
  }

  int total = 0;
}

final _track = Track(
  id: 'server',
  localId: 'local',
  serverTrackId: 'canonical',
  title: 'Track',
  artist: 'Artist',
  album: 'Album',
  durationMs: 1000,
  liked: false,
  inPlaylists: false,
);
final _download = OfflineTrackDownload(
  serverBaseUrl: 'https://music.test',
  track: _track,
  status: OfflineDownloadStatus.downloaded,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
final _album = Album(
  id: 'album',
  title: 'Album',
  artist: 'Artist',
  artistId: 'artist',
  trackCount: 1,
);
final _artist = Artist(id: 'artist', name: 'Artist', albumCount: 1);
final _localAlbum = OfflineAlbumGroup(
  id: 'album',
  title: 'Album',
  artist: 'Artist',
  artistId: 'artist',
  tracks: [_track],
);
final _localArtist = OfflineArtistGroup(
  id: 'artist',
  name: 'Artist',
  albums: [_localAlbum],
);

void main() {
  test('track selection retains the same identity across detail families', () {
    final app = _App();
    final album = AlbumDetailController(app, _album);
    final localAlbum = LocalAlbumDetailController(app, _localAlbum);
    final playlist = PlaylistDetailController(app, 'playlist', false);
    addTearDown(album.dispose);
    addTearDown(localAlbum.dispose);
    addTearDown(playlist.dispose);

    album.toggleSelection(app, _track);
    localAlbum.toggleSelection(_track);
    playlist.enterSelection(app, _track);
    expect(album.selectedTrackIds, {'local'});
    expect(localAlbum.selectedTrackIds, album.selectedTrackIds);
    expect(playlist.selectedTrackIds, album.selectedTrackIds);

    album.deselectAll();
    localAlbum.deselectAll();
    playlist.deselectAll();
    expect(album.selectionMode, isTrue);
    expect(localAlbum.selectionMode, isTrue);
    expect(playlist.selectionMode, isTrue);
    expect(album.selectedTrackIds, isEmpty);
    expect(localAlbum.selectedTrackIds, isEmpty);
    expect(playlist.selectedTrackIds, isEmpty);

    album.clearSelection();
    localAlbum.clearSelection();
    playlist.clearSelection();
    expect(album.selectionMode, isFalse);
    expect(localAlbum.selectionMode, isFalse);
    expect(playlist.selectionMode, isFalse);
  });

  test('selection keeps album and artist identities in their own families', () {
    final app = _App();
    final artist = ArtistDetailController(app, _artist);
    final localArtist = LocalArtistDetailController(app, _localArtist);
    final library = LibraryController(app);
    addTearDown(artist.dispose);
    addTearDown(localArtist.dispose);
    addTearDown(library.dispose);

    artist.toggleAlbumSelection(_album);
    localArtist.toggleAlbumSelection(_localAlbum);
    library.toggleArtistSelection(_localArtist);
    expect(artist.selectedAlbumIds, {'album'});
    expect(localArtist.selectedAlbumIds, {'album'});
    expect(library.selectedArtistIds, {'artist'});

    artist.clearAlbumSelection();
    localArtist.clearAlbumSelection();
    library.clearArtistSelection();
    expect(artist.albumSelectionMode, isFalse);
    expect(localArtist.albumSelectionMode, isFalse);
    expect(library.artistSelectionMode, isFalse);
  });

  test('liked bulk selection notifies once and preserves source groups', () {
    final controller = LikedController(_App());
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);
    controller.selectAll(localTracks: [_track], serverTracks: [_track]);
    expect(changes, 1);
    expect(controller.selectedLocalTrackIds, {'local'});
    expect(controller.selectedServerTrackIds, {'local'});
    controller.toggleSelection(controller.app, _track, local: true);
    expect(changes, 2);
    expect(controller.selectedLocalTrackIds, isEmpty);
    expect(controller.selectedServerTrackIds, {'local'});
    controller.deselectAll();
    expect(changes, 3);
    expect(controller.selectionMode, isTrue);
    expect(controller.selectedServerTrackIds, isEmpty);
    controller.clearSelection();
    expect(changes, 4);
    expect(controller.selectionMode, isFalse);
  });

  test('playlist bulk selection preserves its existing selection mode', () {
    final controller = PlaylistsController(_App());
    addTearDown(controller.dispose);
    final playlist = Playlist(id: 'same', name: 'Playlist', trackIds: []);
    controller.selectAll(
      localPlaylists: [playlist],
      serverPlaylists: [playlist],
    );
    expect(controller.selectionMode, isFalse);
    expect(controller.selectedPlaylistKeys, {'local:same', 'server:same'});
    controller.startSelection();
    controller.toggleSelection(playlist, isLocal: true);
    expect(controller.selectionMode, isTrue);
    expect(controller.selectedPlaylistKeys, {'local:same'});
    controller.deselectAll();
    expect(controller.selectionMode, isTrue);
    expect(controller.selectedPlaylistKeys, isEmpty);
  });

  test('all bound streams stop at the controller lifetime boundary', () async {
    var cancellations = 0;
    final first = StreamController<int>(
      sync: true,
      onCancel: () => cancellations++,
    );
    final second = StreamController<int>(
      sync: true,
      onCancel: () => cancellations++,
    );
    addTearDown(first.close);
    addTearDown(second.close);
    final controller = _ObservingController(first.stream, second.stream);
    var changes = 0;
    controller.addListener(() => changes++);
    first.add(1);
    second.add(2);
    expect(controller.total, 3);
    expect(changes, 2);
    controller.dispose();
    first.add(4);
    second.add(8);
    await Future<void>.delayed(Duration.zero);
    expect(cancellations, 2);
    expect(controller.total, 3);
    expect(changes, 2);
  });

  test('library removal state matches every stored alias of a track', () {
    final app = _App()
      ..offlineDownloads = [
        _download.copyWith(
          status: OfflineDownloadStatus.removing,
          localTrackId: ' other-local ',
        ),
      ];
    final library = LibraryController(app);
    final artist = LocalArtistDetailController(app, _localArtist);
    addTearDown(library.dispose);
    addTearDown(artist.dispose);
    final identities = library.removingTrackIds(app);
    expect(identities, {'server', 'canonical', 'local', 'other-local'});
    expect(artist.removingTrackIds(app), identities);
    expect(library.groupHasRemovingTracks(_localArtist, identities), isTrue);
    expect(artist.albumHasRemovingTracks(_localAlbum, identities), isTrue);
  });
}
