import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/auth/login_controller.dart';
import 'package:phonolite_app/application/controllers/auth/password_change_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_navigation_controller.dart';
import 'package:phonolite_app/application/controllers/playback/device_picker_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/add_to_playlist_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_editor_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_image_edit.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_browse_snapshot.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/application/controllers/library/album_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/artist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/playback/shuffle_presets_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlists_controller.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/projections/library/offline_album_group.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

class _Connection extends Fake implements ServerConnection {
  @override
  int sessionRevision = 0;
  @override
  String baseUrl = 'https://music.test:3000';
  final albumRequest = Completer<Album>();
  int artistRequests = 0;
  @override
  Future<Album> fetchAlbumById(String id) => albumRequest.future;
  @override
  Future<Artist> fetchArtistById(String id) async {
    artistRequests++;
    return Artist(id: id, name: 'Artist', albumCount: 1);
  }
}

class _App extends Fake implements AppController {
  @override
  final _Connection connection = _Connection();
  @override
  late final catalog = CatalogController(connection);
  @override
  Future<Artist> fetchArtistMetadata(String id, {bool refresh = false}) => catalog.fetchArtistById(id);

  final authEvents = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState authState = AuthState(isAuthorized: true, baseUrl: 'https://music.test:3000');
  @override
  Stream<AuthState> get authStream => authEvents.stream;
  final searches = <String>[];
  final playlistLoads = <String, Completer<void>>{};
  int passwordSubmissions = 0;
  int probes = 0;
  int logins = 0;

  @override
  Future<void> search(String query, {String filter = 'all'}) async => searches.add('$query:$filter');
  @override
  Future<bool> probeServer(String input) async {
    probes++;
    return true;
  }

  @override
  Future<void> loginWithPassword({
    required String baseUrl,
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    logins++;
  }

  @override
  Future<void> resetUserPassword({required String currentPassword, required String newPassword}) async {
    passwordSubmissions++;
  }

  @override
  Future<void> loadPlaylistTracks(String id) => (playlistLoads[id] = Completer<void>()).future;

  @override
  ArtistBrowseSnapshot artistBrowseSnapshot = const ArtistBrowseSnapshot();

  @override
  bool artistsLoading = false;

  @override
  bool hasMoreArtists = true;

  final browsePageRequests = <int>[];
  Object? browsePageFailure;
  int moreArtistLoads = 0;

  @override
  Future<void> loadArtistBrowsePage(int index) async {
    browsePageRequests.add(index);

    if (browsePageFailure != null) {
      throw browsePageFailure!;
    }
  }

  @override
  Future<void> loadMoreArtists() async => moreArtistLoads++;

  @override
  Stream<Artist> watchArtist(String artistId) => const Stream.empty();

  final playlistCommands = <String>[];

  @override
  Future<void> playPlaylistFromTop(String playlistId) async => playlistCommands.add('server:play:$playlistId');

  @override
  Future<void> playLocalPlaylistFromTop(String playlistId) async => playlistCommands.add('local:play:$playlistId');

  @override
  Future<void> queuePlaylist(String playlistId, {String? startTrackId}) async =>
      playlistCommands.add('server:queue:$playlistId:$startTrackId');

  @override
  Future<void> queueLocalPlaylist(String playlistId, {String? startTrackId}) async =>
      playlistCommands.add('local:queue:$playlistId:$startTrackId');

  @override
  Future<void> renamePlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async => playlistCommands.add('server:rename:$playlistId:$name');

  @override
  Future<void> renameLocalPlaylist(
    String playlistId,
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) async => playlistCommands.add('local:rename:$playlistId:$name');

  @override
  Future<void> toggleLike(Track track) async => playlistCommands.add('server:like:${track.id}');

  @override
  Future<void> toggleLocalLike(Track track) async => playlistCommands.add('local:like:${track.id}');

  @override
  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => playlistCommands.add('server:create:$name');

  @override
  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => playlistCommands.add('local:create:$name');

  final playbackCommands = <String>[];

  @override
  void updateShuffleMode(ShuffleMode mode, {ActionScope? scope}) =>
      playbackCommands.add('shuffle:${mode.name}:${scope?.name}');

  @override
  Future<void> queueAlbum(String albumId, {String? startTrackId}) async => playbackCommands.add('queue:$albumId');

  @override
  List<ShufflePreset> shufflePresets = const [];

  @override
  bool shufflePresetsAvailable = true;

  final deletedPresetIds = <String>[];

  @override
  Future<void> deleteShufflePreset(ShufflePreset preset) async => deletedPresetIds.add(preset.id);

  @override
  Future<void> close() => authEvents.close();
}

void main() {
  test('sign in controller validates ports before probing and requires credentials after connecting', () async {
    final app = _App();
    final controller = LoginController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    await controller.submit(host: 'music.test', port: '65536', username: '', password: '');
    expect(app.probes, 0);
    expect(controller.error, contains('Port'));
    await controller.submit(host: 'music.test', port: '3000', username: '', password: '');
    expect(controller.connected, isTrue);
    await controller.submit(host: 'music.test', port: '3000', username: '', password: '');
    expect(app.logins, 0);
    expect(controller.error, contains('Username and password'));
    expect(controller.isSubmitting, isFalse);
  });

  test('server address parsing preserves proxy paths, query and explicit port', () {
    final app = _App();
    final controller = LoginController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final address = controller.normalizeAddress('https://music.test:8443/proxy/api');
    expect(address.host, 'music.test/proxy');
    expect(address.port, '8443');
    expect(
      controller.resolveBaseUrl('music.test/proxy?tenant=one', '8443'),
      'https://music.test:8443/proxy?tenant=one',
    );
  });

  test('password controller invalidates a form after account change', () async {
    final app = _App();
    final controller = PasswordChangeController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    app.connection.sessionRevision++;
    app.authEvents.add(app.authState);
    expect(controller.sessionChanged, isTrue);
    expect(controller.clearPasswordsRevision, 1);
    await controller.submit(currentPassword: 'old', newPassword: 'new', confirmation: 'new');
    expect(app.passwordSubmissions, 0);
  });

  test('password validation uses UTF-8 length and never submits mismatched confirmation', () async {
    final app = _App();
    final controller = PasswordChangeController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    await controller.submit(currentPassword: 'old', newPassword: 'é' * 513, confirmation: 'é' * 513);
    expect(controller.error, 'Your new password is too long.');
    await controller.submit(currentPassword: 'old', newPassword: 'new', confirmation: 'different');
    expect(controller.error, 'The new passwords do not match.');
    expect(app.passwordSubmissions, 0);
  });

  testWidgets('library debounce submits only the latest query and is canceled on disposal', (tester) async {
    final app = _App();
    final controller = LibraryController(app);
    controller.setQuery('first');
    controller.queueSearch(app);
    await tester.pump(const Duration(milliseconds: 300));
    controller.setQuery('second');
    controller.queueSearch(app);
    await tester.pump(const Duration(milliseconds: 450));
    expect(app.searches, ['second:all']);
    controller.setQuery('third');
    controller.queueSearch(app);
    controller.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(app.searches, ['second:all']);
    await app.close();
  });

  test('a visible unloaded windowed row requests its page and a failed request stays contained', () async {
    final app = _App()..artistBrowseSnapshot = const ArtistBrowseSnapshot(total: 500);
    final controller = LibraryController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);

    expect(controller.serverArtistIndices(const []), hasLength(500));
    expect(controller.serverArtistAt(120, const []), isNull);

    controller.serverArtistRowVisibilityChanged(120, false, artists: const [], libraryLocalFirst: false);
    controller.serverArtistRowVisibilityChanged(120, true, artists: const [], libraryLocalFirst: false);
    app.browsePageFailure = StateError('Artist browse capacity reached');
    controller.serverArtistRowVisibilityChanged(499, true, artists: const [], libraryLocalFirst: false);
    await Future<void>.delayed(Duration.zero);

    expect(app.browsePageRequests, [120, 499]);
    expect(app.moreArtistLoads, 0);
  });

  test('the legacy roster loads its next page at the last row unless local sections come first', () {
    final app = _App();
    final controller = LibraryController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final artists = [
      for (var index = 0; index < 3; index++) Artist(id: 'artist-$index', name: 'A$index', albumCount: 1),
    ];

    expect(controller.serverArtistIndices(artists), [0, 1, 2]);

    controller.serverArtistRowVisibilityChanged(2, true, artists: artists, libraryLocalFirst: true);

    expect(app.moreArtistLoads, 0);

    app.artistsLoading = true;
    controller.serverArtistRowVisibilityChanged(2, true, artists: artists, libraryLocalFirst: false);

    expect(app.moreArtistLoads, 0);

    app.artistsLoading = false;
    controller.serverArtistRowVisibilityChanged(2, true, artists: artists, libraryLocalFirst: false);

    expect(app.moreArtistLoads, 1);
    expect(app.browsePageRequests, isEmpty);
  });

  test('the remaining scroll extent decides legacy paging and windowed catalogues ignore it', () {
    final app = _App();
    final controller = LibraryController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);

    controller.loadMoreArtists(721);
    controller.loadMoreArtists(720);

    expect(app.moreArtistLoads, 1);

    controller.setQuery('search');
    controller.loadMoreArtists(0);
    controller.setQuery('');
    app.artistBrowseSnapshot = const ArtistBrowseSnapshot(total: 500);
    controller.loadMoreArtists(0);

    expect(app.moreArtistLoads, 1);
  });

  test('playlist detail resolves its playlist and entries and hides tracks while loading', () async {
    final app = _App();
    final controller = PlaylistDetailController(app, 'mix', true);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final track = Track(
      id: 'track',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1,
      liked: false,
      inPlaylists: true,
    );
    final mix = Playlist(id: 'mix', name: 'Mix', trackIds: const ['track']);

    expect(controller.playlistFrom([Playlist(id: 'other', name: 'Other', trackIds: const []), mix]), same(mix));
    expect(controller.playlistFrom(const []).id, 'mix');
    expect(
      controller
          .entriesFrom([
            LocalPlaylistEntry(
              entryKey: 'other:0',
              playlistId: 'other',
              position: 0,
              track: track,
              status: OfflineDownloadStatus.downloaded,
              isPending: false,
            ),
            LocalPlaylistEntry(
              entryKey: 'mix:0',
              playlistId: 'mix',
              position: 0,
              track: track,
              status: OfflineDownloadStatus.downloaded,
              isPending: false,
            ),
          ])
          .map((entry) => entry.entryKey),
      ['mix:0'],
    );
    expect(controller.actionScope, ActionScope.local);

    final server = PlaylistDetailController(app, 'mix', false);
    addTearDown(server.dispose);

    expect(server.displayedTracks([track]), isEmpty);

    server.loadTracksIfNeeded(app);
    app.playlistLoads['mix']!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(server.displayedTracks([track]), [track]);
    expect(server.actionScope, ActionScope.server);
  });

  test('playlist detail routes commands to the local or server playlist it shows', () async {
    final app = _App();
    final track = Track(
      id: 'track',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1,
      liked: false,
      inPlaylists: true,
    );
    addTearDown(app.close);

    for (final local in [true, false]) {
      final controller = PlaylistDetailController(app, 'mix', local);
      addTearDown(controller.dispose);

      await controller.playFromTop();
      await controller.playFrom(track);
      await controller.rename('Renamed');
      await controller.toggleLike(track);
    }

    expect(app.playlistCommands, [
      'local:play:mix',
      'local:queue:mix:track',
      'local:rename:mix:Renamed',
      'local:like:track',
      'server:play:mix',
      'server:queue:mix:track',
      'server:rename:mix:Renamed',
      'server:like:track',
    ]);
  });

  test('local artists are selectable only when they have downloaded tracks', () {
    final app = _App();
    final controller = LibraryController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final track = Track(
      id: 'track',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1,
      liked: false,
      inPlaylists: false,
    );
    final withTracks = OfflineArtistGroup(
      id: 'artist',
      name: 'Artist',
      albums: [
        OfflineAlbumGroup(id: 'album', title: 'Album', artist: 'Artist', artistId: 'artist', tracks: [track]),
      ],
    );
    const empty = OfflineArtistGroup(id: 'empty', name: 'Empty', albums: []);

    expect(controller.hasRemovableTracks(withTracks), isTrue);
    expect(controller.hasRemovableTracks(empty), isFalse);
    expect(controller.selectableArtistGroups([withTracks, empty]), [withTracks]);
    expect(controller.canSelectArtistGroup(withTracks, const {}), isTrue);
    expect(controller.canSelectArtistGroup(empty, const {}), isFalse);
  });

  test('artist albums are selectable when removable and not already being removed', () {
    final app = _App();
    final controller = ArtistDetailController(app, Artist(id: 'artist', name: 'Artist', albumCount: 2));
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final album = Album(id: 'album', title: 'Album', artist: 'Artist', artistId: 'artist', trackCount: 1);

    expect(controller.canSelectAlbum(album, removableIds: {'album'}, removingIds: const {}), isTrue);
    expect(controller.canSelectAlbum(album, removableIds: const {}, removingIds: const {}), isFalse);
    expect(controller.canSelectAlbum(album, removableIds: {'album'}, removingIds: {'album'}), isFalse);
    expect(controller.isRemovingAlbum(album, {'album'}), isTrue);
    expect(
      controller.canSelectContribution(
        ArtistReleaseContribution(album: album, roles: const ['album_artist']),
        removableIds: {'album'},
        removingIds: const {},
      ),
      isTrue,
    );
    expect(
      controller.canSelectContribution(
        ArtistReleaseContribution(album: album, roles: const ['featured']),
        removableIds: {'album'},
        removingIds: const {},
      ),
      isFalse,
    );
  });

  test('a shuffle deletion confirmed after the session changed deletes nothing', () async {
    final app = _App()
      ..shufflePresets = [ShufflePreset(id: 'preset', name: 'Mix', artistIds: const [], genres: const [], revision: 1)];
    final controller = ShufflePresetsController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    controller.toggleSelection('preset');

    final stale = controller.beginDeletion();
    app.connection.sessionRevision++;
    await controller.delete(stale);

    expect(app.deletedPresetIds, isEmpty);

    await controller.delete(controller.beginDeletion());

    expect(app.deletedPresetIds, ['preset']);
  });

  test('playlist creation uses the chosen target and falls back to the device when signed out', () async {
    final app = _App();
    final controller = PlaylistsController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    const keep = PlaylistImageEdit.keep();

    await controller.createPlaylist('A', description: '', imageEdit: keep, target: PlaylistEditorTarget.server);
    await controller.createPlaylist('B', description: '', imageEdit: keep, target: PlaylistEditorTarget.local);
    app.authState = AuthState(isAuthorized: false, baseUrl: 'https://music.test:3000');
    await controller.createPlaylist('C', description: '', imageEdit: keep, target: PlaylistEditorTarget.server);

    expect(app.playlistCommands, ['server:create:A', 'local:create:B', 'local:create:C']);
  });

  test('playing an album in order turns server shuffle off before queueing it', () async {
    final app = _App();
    final album = Album(id: 'album', title: 'Album', artist: 'Artist', artistId: 'artist', trackCount: 1);
    final controller = AlbumDetailController(app, album);
    addTearDown(controller.dispose);
    addTearDown(app.close);

    await controller.playInOrder();

    expect(app.playbackCommands, ['shuffle:off:server', 'queue:album']);
  });

  test('device refresh ignores an older completion', () async {
    final requests = <Completer<List<OutputDevice>>>[];
    final controller = DevicePickerController((_) {
      final request = Completer<List<OutputDevice>>();
      requests.add(request);
      return request.future;
    });
    addTearDown(controller.dispose);
    final first = controller.loadDevices();
    final second = controller.loadDevices(refresh: true);
    requests[1].complete([OutputDevice(id: 2, name: 'New')]);
    await second;
    requests[0].complete([OutputDevice(id: 1, name: 'Old')]);
    await first;
    expect(controller.devices.single.id, 2);
    expect(controller.loading, isFalse);
  });

  test('late device completion sends no notification after disposal', () async {
    final request = Completer<List<OutputDevice>>();
    final controller = DevicePickerController((_) => request.future);
    var changes = 0;
    controller.addListener(() => changes++);
    final loading = controller.loadDevices();
    controller.dispose();
    request.complete([]);
    await loading;
    expect(changes, 1);
  });

  test('playlist loading cannot be completed by a previous playlist request', () async {
    final app = _App();
    final controller = PlaylistDetailController(app, 'first', false);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    controller.loadTracksIfNeeded(app);
    controller.setPlaylist('second', false);
    app.playlistLoads['first']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.tracksLoading, isTrue);
    app.playlistLoads['second']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.tracksLoading, isFalse);
  });

  test('navigation discards metadata after a session changes', () async {
    final app = _App();
    final controller = LibraryNavigationController(app);
    addTearDown(controller.dispose);
    addTearDown(app.close);
    final result = controller.search(SearchResult(kind: 'album', id: 'album', title: 'Album'), local: false);
    app.connection.sessionRevision++;
    app.connection.albumRequest.complete(
      Album(id: 'album', title: 'Album', artist: 'Artist', artistId: 'artist', trackCount: 1),
    );
    expect(await result, isNull);
    expect(app.connection.artistRequests, 0);
  });

  test('playlist edits serialize submission and report failure without navigation', () async {
    final save = Completer<void>();
    var calls = 0;
    final controller = PlaylistEditorController((name, description, image, target) {
      calls++;
      return save.future;
    }, PlaylistEditorTarget.local);
    addTearDown(controller.dispose);
    final first = controller.submit('Name', 'Description');
    expect(await controller.submit('Duplicate', ''), isFalse);
    save.completeError(StateError('failed'));
    expect(await first, isFalse);
    expect(calls, 1);
    expect(controller.saving, isFalse);
    expect(controller.imageError, 'Failed to save playlist.');
  });

  test('playlist membership projection keeps counts consistent through add/remove', () async {
    final controller = AddToPlaylistController();
    addTearDown(controller.dispose);
    final playlist = Playlist(id: 'playlist', name: 'Playlist', trackIds: []);
    await controller.add(playlist, (_) {});
    expect(controller.contains(playlist, 'track'), isTrue);
    expect(controller.trackCount(playlist, 'track'), 1);
    await controller.remove(playlist, (_) {});
    expect(controller.contains(playlist, 'track'), isFalse);
    expect(controller.trackCount(playlist, 'track'), 0);
  });
}
