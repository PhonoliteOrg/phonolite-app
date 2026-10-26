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
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
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

  test('playlist membership projection keeps counts consistent through add/remove', () {
    final controller = AddToPlaylistController();
    addTearDown(controller.dispose);
    final playlist = Playlist(id: 'playlist', name: 'Playlist', trackIds: []);
    controller.add(playlist, (_) {});
    expect(controller.contains(playlist, 'track'), isTrue);
    expect(controller.trackCount(playlist, 'track'), 1);
    controller.remove(playlist, (_) {});
    expect(controller.contains(playlist, 'track'), isFalse);
    expect(controller.trackCount(playlist, 'track'), 0);
  });
}
