import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/favorites/liked_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlists_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/shared/music/artwork/authenticated_network_image.dart';

import '../support/artwork_test_loader.dart';

void main() {
  test('liked and playlist screens reload after switching accounts on the same server', () async {
    final app = _App();
    final liked = LikedController(app);
    final playlists = PlaylistsController(app);
    addTearDown(liked.dispose);
    addTearDown(playlists.dispose);
    addTearDown(app.authEvents.close);
    await Future.wait([liked.initialize(), playlists.initialize()]);
    expect(app.likeLoads, 1);
    expect(app.playlistLoads, 1);
    app.authEvents.add(app.authState);
    expect(app.likeLoads, 1);
    expect(app.playlistLoads, 1);

    app.connection.sessionRevision++;
    app.authEvents.add(app.authState);
    expect(app.likeLoads, 2);
    expect(app.playlistLoads, 2);
    expect(app.localLikeLoads, 1);
    expect(app.localPlaylistLoads, 1);
  });

  test('decoded artwork caches separate accounts requesting the same private cover URL', () {
    const url = 'https://music.test/api/library/playlists/old-list/cover';
    final headers = {'Authorization': 'Bearer first'};
    const loader = ArtworkTestLoader();
    final first = AuthenticatedNetworkImage(url, loader: loader, headers: headers);
    final firstAgain = AuthenticatedNetworkImage(url, loader: loader, headers: {'Authorization': 'Bearer first'});
    final second = AuthenticatedNetworkImage(url, loader: loader, headers: {'Authorization': 'Bearer second'});
    final signedOut = AuthenticatedNetworkImage(url, loader: loader);
    expect(first, firstAgain);
    expect(first.hashCode, firstAgain.hashCode);
    expect(first, isNot(second));
    expect(first, isNot(signedOut));
    headers['Authorization'] = 'Bearer second';
    expect(first, firstAgain);
    expect(first, isNot(second));
  });
}

class _Connection extends Fake implements ServerConnection {
  @override
  int sessionRevision = 1;
}

class _App extends Fake implements AppController {
  @override
  final _Connection connection = _Connection();
  final authEvents = StreamController<AuthState>.broadcast(sync: true);
  int likeLoads = 0;
  int playlistLoads = 0;
  int localLikeLoads = 0;
  int localPlaylistLoads = 0;

  @override
  AuthState get authState => AuthState(isAuthorized: true, baseUrl: 'https://music.test/api');
  @override
  Stream<AuthState> get authStream => authEvents.stream;
  @override
  Future<void> loadLikedTracks() async => likeLoads++;
  @override
  Future<void> loadPlaylists() async => playlistLoads++;
  @override
  Future<void> loadLocalLikedTracks() async => localLikeLoads++;
  @override
  Future<void> loadLocalPlaylists() async => localPlaylistLoads++;
}
