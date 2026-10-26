import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/favorites/liked_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/library/album_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/artist_detail_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/controllers/listening_stats/stats_controller.dart';
import 'package:phonolite_app/application/controllers/playback/custom_shuffle_controller.dart';
import 'package:phonolite_app/application/controllers/playback/device_picker_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_editor_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlists_controller.dart';
import 'package:phonolite_app/application/controllers/settings/listening_statistics_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

final _artist = Artist(id: 'artist', name: 'Artist', albumCount: 1);
final _album = Album(id: 'album', title: 'Album', artist: 'Artist', artistId: 'artist', trackCount: 1);

class _Connection extends Fake implements ServerConnection {
  final List<String> calls;
  @override
  int sessionRevision = 0;

  _Connection(this.calls);

  @override
  Future<Artist> fetchArtistById(String id) async {
    calls.add('artist');

    return _artist;
  }
}

class _App extends Fake implements AppController {
  final List<String> calls = [];
  Completer<void>? localCollectionLoad;
  Completer<void>? serverCollectionLoad;
  @override
  late final _Connection connection = _Connection(calls);
  @override
  late final catalog = CatalogController(connection);
  @override
  Future<Artist> fetchArtistMetadata(String id, {bool refresh = false}) => catalog.fetchArtistById(id);

  @override
  AuthState authState = AuthState(isAuthorized: true, baseUrl: 'https://test.invalid');
  @override
  List<Artist> get artists => const [];
  @override
  List<Playlist> get playlists => const [];
  @override
  List<Track> get liked => const [];
  @override
  CustomShuffleSettings get customShuffleSettings => const CustomShuffleSettings();
  @override
  Stream<AuthState> get authStream => const Stream.empty();
  @override
  Stream<List<Artist>> get artistsStream => const Stream.empty();
  @override
  Stream<OfflineLibrarySnapshot> get offlineLibrarySnapshotStream => const Stream.empty();
  @override
  Stream<Album> watchAlbum(String id) => const Stream.empty();
  @override
  Stream<Artist> watchArtist(String id) => const Stream.empty();
  @override
  Future<void> loadTracks(String id) async => calls.add('tracks');
  @override
  Future<void> loadArtistReleases(String id) async => calls.add('releases');
  @override
  Future<void> loadLocalPlaylists() {
    calls.add('local playlists');

    return localCollectionLoad?.future ?? Future<void>.value();
  }

  @override
  Future<void> loadPlaylists() {
    calls.add('playlists');

    return serverCollectionLoad?.future ?? Future<void>.value();
  }

  @override
  Future<void> loadLocalLikedTracks() {
    calls.add('local liked');

    return localCollectionLoad?.future ?? Future<void>.value();
  }

  @override
  Future<void> loadLikedTracks() {
    calls.add('liked');

    return serverCollectionLoad?.future ?? Future<void>.value();
  }

  @override
  Future<void> loadArtists({bool refresh = false}) async => calls.add('artists');
  @override
  Future<void> loadStats({int? year, int? month}) async => calls.add('stats');
  @override
  Future<void> resetListeningStatistics() async => calls.add('reset');

  @override
  Future<void> updateCustomShuffleSettings({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) async {}
}

class _FailingDownloads extends Fake implements OfflineDownloadManager {
  @override
  Future<Playlist> createLocalPlaylist(String name, {String? description}) => Future.error(StateError('write failed'));

  @override
  Future<Playlist?> renameLocalPlaylist(String id, String name, {String? description}) =>
      Future.error(StateError('write failed'));

  @override
  Future<void> dispose() async {}
}

class _ReentrantController extends FeatureController {
  int calls = 0;
  Future<void>? nestedInitialization;

  @override
  void initializeFeature() {
    calls++;
    nestedInitialization = initialize();
  }
}

void main() {
  test('synchronous initialization reentry shares the same work', () async {
    final controller = _ReentrantController();
    addTearDown(controller.dispose);

    final initialization = controller.initialize();

    expect(controller.nestedInitialization, same(initialization));
    await initialization;
    expect(controller.calls, 1);
  });

  test('feature construction is inert and initialization runs the initial loads once', () async {
    final app = _App();
    final controllers = [
      AlbumDetailController(app, _album),
      ArtistDetailController(app, _artist),
      PlaylistsController(app),
      LikedController(app),
      StatsController(app),
      CustomShuffleController(app),
    ];
    for (final controller in controllers) {
      addTearDown(controller.dispose);
    }

    expect(app.calls, isEmpty);

    for (final controller in controllers) {
      await controller.initialize();
      await controller.initialize();
    }

    expect(app.calls, [
      'tracks',
      'releases',
      'artist',
      'local playlists',
      'playlists',
      'local liked',
      'liked',
      'stats',
      'artists',
    ]);
  });

  for (final liked in [false, true]) {
    test('${liked ? 'liked' : 'playlist'} initialization waits for both collection sources', () async {
      final app = _App();
      final local = Completer<void>();
      final server = Completer<void>();
      app.localCollectionLoad = local;
      app.serverCollectionLoad = server;
      final controller = liked ? LikedController(app) : PlaylistsController(app);
      addTearDown(controller.dispose);
      var completed = false;

      final initialization = controller.initialize();
      initialization.then((_) => completed = true);
      expect(controller.initialize(), same(initialization));
      expect(app.calls, liked ? ['local liked', 'liked'] : ['local playlists', 'playlists']);

      local.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      server.complete();
      await initialization;
      expect(completed, isTrue);
      expect(app.calls.length, 2);
    });
  }

  test('selection observations cannot bypass notifications or disposal', () {
    final controller = AlbumDetailController(_App(), _album);
    var changes = 0;
    controller.addListener(() => changes++);

    expect(() => controller.selectedTrackIds.add('outside'), throwsUnsupportedError);
    controller.selectionMode = true;
    expect(changes, 1);
    expect(controller.selectionMode, isTrue);

    controller.dispose();
    controller.selectionMode = false;
    controller.clearSelection();

    expect(controller.selectionMode, isTrue);
    expect(changes, 1);
  });

  test('disposing before initialization does not start external work', () async {
    final app = _App();
    final controller = LikedController(app);
    controller.dispose();

    await controller.initialize();

    expect(app.calls, isEmpty);
  });

  test('device observations do not expose the controller backing list', () async {
    final controller = DevicePickerController((_) async => [OutputDevice(id: 1, name: 'Speakers')]);
    addTearDown(controller.dispose);

    await controller.loadDevices();

    expect(() => controller.devices.clear(), throwsUnsupportedError);
    expect(controller.devices.single.id, 1);
  });

  test('statistics reset checks the session captured before confirmation', () async {
    final app = _App();
    final revision = app.connection.sessionRevision;

    await ListeningStatisticsController.resetForSession(app, serverConnected: true, sessionRevision: revision);
    expect(app.calls, ['reset']);

    app.connection.sessionRevision++;
    await expectLater(
      ListeningStatisticsController.resetForSession(app, serverConnected: true, sessionRevision: revision),
      throwsStateError,
    );
    expect(app.calls, ['reset']);
  });

  for (final rename in [false, true]) {
    test('failed local playlist ${rename ? 'rename' : 'creation'} remains an editor failure', () async {
      final app = AppController(
        connection: ServerConnection(baseUrl: 'https://test.invalid'),
        offlineDownloadManager: _FailingDownloads(),
      );
      addTearDown(app.close);
      final editor = PlaylistEditorController(
        (name, description, image, target) => rename
            ? app.renameLocalPlaylist('playlist', name, description: description, imageEdit: image)
            : app.createLocalPlaylist(name, description: description, imageEdit: image),
        PlaylistEditorTarget.local,
      );
      addTearDown(editor.dispose);

      expect(await editor.submit('Name', 'Description'), isFalse);
      expect(editor.imageError, 'Failed to save playlist.');
      expect(editor.saving, isFalse);
    });
  }
}
