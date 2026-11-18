import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/favorites/liked_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist_image_edit.dart';
import 'package:phonolite_app/data/models/collections/playlist_editor_values.dart';
import 'package:phonolite_app/data/models/library/track.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('local target creates a local playlist from local liked tracks in shown order', () async {
    final app = _App(localLiked: [_track('l2'), _track('l1')], liked: [_track('s1')]);
    final liked = LikedController(app);
    addTearDown(liked.dispose);
    const image = PlaylistImageEdit.keep();

    await liked.createPlaylistFromLiked(
      'Favorites',
      description: 'Mine',
      imageEdit: image,
      target: PlaylistEditorTarget.local,
    );

    expect(app.calls, ['local:Favorites:Mine:l2,l1']);
  });

  test('server target creates a server playlist from server liked tracks in shown order', () async {
    final app = _App(localLiked: [_track('l1')], liked: [_track('s3'), _track('s1'), _track('s2')]);
    final liked = LikedController(app);
    addTearDown(liked.dispose);

    await liked.createPlaylistFromLiked(
      'Favorites',
      description: '',
      imageEdit: const PlaylistImageEdit.keep(),
      target: PlaylistEditorTarget.server,
    );

    expect(app.calls, ['server:Favorites::s3,s1,s2']);
  });

  test('playlist message names the target source and its current liked-track count', () {
    final liked = LikedController(_App(localLiked: [_track('l1')], liked: [_track('s1'), _track('s2')]));
    addTearDown(liked.dispose);

    expect(
      liked.playlistMessageFor(PlaylistEditorTarget.local),
      'Your 1 local liked track will be added to this new local playlist, in the order shown.',
    );
    expect(
      liked.playlistMessageFor(PlaylistEditorTarget.server),
      'Your 2 server liked tracks will be added to this new server playlist, in the order shown.',
    );
  });

  test('playlist target defaults to the only source with liked tracks, else the first shown', () {
    final liked = LikedController(_App());
    addTearDown(liked.dispose);
    final some = [_track('a')];

    expect(
      liked.playlistTargetFor(localTracks: some, serverTracks: const [], localFirst: false),
      PlaylistEditorTarget.local,
    );
    expect(
      liked.playlistTargetFor(localTracks: const [], serverTracks: some, localFirst: true),
      PlaylistEditorTarget.server,
    );
    expect(
      liked.playlistTargetFor(localTracks: some, serverTracks: some, localFirst: true),
      PlaylistEditorTarget.local,
    );
    expect(
      liked.playlistTargetFor(localTracks: some, serverTracks: some, localFirst: false),
      PlaylistEditorTarget.server,
    );
  });
}

Track _track(String id) => offlineTestTrack(id: id, title: id);

class _App extends Fake implements AppController {
  @override
  final List<Track> localLiked;
  @override
  final List<Track> liked;
  final calls = <String>[];

  _App({this.localLiked = const [], this.liked = const []});

  @override
  AuthState get authState => AuthState(isAuthorized: true, baseUrl: 'https://music.test/api');

  @override
  Future<void> createLocalPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => calls.add('local:$name:$description:${tracks.map((track) => track.id).join(',')}');

  @override
  Future<void> createPlaylist(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
    List<Track> tracks = const <Track>[],
  }) async => calls.add('server:$name:$description:${tracks.map((track) => track.id).join(',')}');
}
