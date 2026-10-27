import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUp(configureTestFonts);

  testWidgets('open playlist choices follow authoritative changes and clear optimistic membership', (tester) async {
    final updates = StreamController<List<Playlist>>.broadcast();
    addTearDown(updates.close);
    final additions = <String>[];
    await tester.pumpWidget(
      wrapInTestApp(
        AddToPlaylistModal(
          scope: ActionScope.server,
          playlists: [_playlist('mix', 'Original')],
          playlistChanges: updates.stream,
          trackId: 'track',
          canUsePlaylists: true,
          onSelected: (playlist) => additions.add(playlist.id),
          onRemoved: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    expect(additions, ['mix']);
    expect(find.byTooltip('Remove from playlist'), findsOneWidget);
    expect(find.text('Server - 1 tracks'), findsOneWidget);

    updates.add([_playlist('mix', 'Renamed elsewhere')]);
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsNothing);
    expect(find.text('Renamed elsewhere'), findsOneWidget);
    expect(find.byTooltip('Add to playlist'), findsOneWidget);
    expect(find.text('Server - 0 tracks'), findsOneWidget);

    updates.add([
      _playlist('mix', 'Renamed elsewhere', trackIds: ['track']),
      _playlist('new', 'New playlist'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('New playlist'), findsOneWidget);
    expect(find.byTooltip('Remove from playlist'), findsOneWidget);
    expect(find.byTooltip('Add to playlist'), findsOneWidget);

    updates.add([_playlist('new', 'New playlist')]);
    await tester.pumpAndSettle();
    expect(find.text('Renamed elsewhere'), findsNothing);
    expect(find.text('New playlist'), findsOneWidget);

    updates.add([]);
    await tester.pumpAndSettle();
    expect(find.text('No server playlists available.'), findsOneWidget);
    expect(find.text('New playlist'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(updates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the playlist source releases the old subscription', (tester) async {
    final oldUpdates = StreamController<List<Playlist>>.broadcast();
    final newUpdates = StreamController<List<Playlist>>.broadcast();
    addTearDown(oldUpdates.close);
    addTearDown(newUpdates.close);

    Widget modal(Stream<List<Playlist>> updates, List<Playlist> playlists) => wrapInTestApp(
      AddToPlaylistModal(
        key: const ValueKey('same-modal'),
        scope: ActionScope.server,
        playlists: playlists,
        playlistChanges: updates,
        trackId: 'track',
        canUsePlaylists: true,
        onSelected: (_) {},
      ),
    );

    await tester.pumpWidget(modal(oldUpdates.stream, [_playlist('old', 'Old source')]));
    await tester.pumpAndSettle();
    expect(oldUpdates.hasListener, isTrue);

    await tester.pumpWidget(modal(newUpdates.stream, [_playlist('new', 'Replacement')]));
    await tester.pumpAndSettle();
    expect(oldUpdates.hasListener, isFalse);
    expect(newUpdates.hasListener, isTrue);
    oldUpdates.add([_playlist('late', 'Late old source')]);
    newUpdates.add([_playlist('new', 'Current source')]);
    await tester.pumpAndSettle();

    expect(find.text('Late old source'), findsNothing);
    expect(find.text('Current source'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(newUpdates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updating initial playlists retains the existing single-subscription source', (tester) async {
    final updates = StreamController<List<Playlist>>();
    addTearDown(updates.close);

    Widget modal(String name) => wrapInTestApp(
      AddToPlaylistModal(
        key: const ValueKey('same-modal'),
        scope: ActionScope.server,
        playlists: [_playlist('mix', name)],
        playlistChanges: updates.stream,
        trackId: 'track',
        canUsePlaylists: true,
        onSelected: (_) {},
      ),
    );

    await tester.pumpWidget(modal('Initial'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(modal('Updated input'));
    await tester.pumpAndSettle();
    expect(find.text('Updated input'), findsOneWidget);

    updates.add([_playlist('mix', 'Still subscribed')]);
    await tester.pumpAndSettle();
    expect(find.text('Still subscribed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a server modal clears on account switch and never displays another accounts playlists', (tester) async {
    final app = _App();
    addTearDown(app.close);
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: wrapInTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddToPlaylistModalForTrack(context, _track(), scope: ActionScope.server),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Alice mix'), findsOneWidget);

    app.serverPlaylists = [_playlist('alice', 'Alice renamed')];
    app.playlistChanges.add(app.serverPlaylists);
    await tester.pumpAndSettle();
    expect(find.text('Alice renamed'), findsOneWidget);

    app.connection.sessionRevision++;
    app.authorized = false;
    app.authChanges.add(app.authState);
    await tester.pumpAndSettle();
    expect(find.text('Alice renamed'), findsNothing);
    expect(find.text('No server playlists available.'), findsOneWidget);

    app.authorized = true;
    app.serverPlaylists = [_playlist('bob', 'Bob private mix')];
    app.authChanges.add(app.authState);
    app.playlistChanges.add(app.serverPlaylists);
    await tester.pumpAndSettle();
    expect(find.text('Bob private mix'), findsNothing);
    expect(find.text('No server playlists available.'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(app.playlistChanges.hasListener, isFalse);
    expect(app.authChanges.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Playlist _playlist(String id, String name, {List<String> trackIds = const []}) =>
    Playlist(id: id, name: name, trackIds: trackIds);

Track _track() => Track(
  id: 'track',
  title: 'Track',
  artist: 'Artist',
  album: 'Album',
  durationMs: 180000,
  liked: false,
  inPlaylists: false,
);

class _Connection extends Fake implements ServerConnection {
  @override
  int sessionRevision = 1;
}

class _App extends Fake implements AppController {
  @override
  final _Connection connection = _Connection();
  @override
  late final catalog = CatalogController(connection);
  final playlistChanges = StreamController<List<Playlist>>.broadcast();
  final authChanges = StreamController<AuthState>.broadcast();
  List<Playlist> serverPlaylists = [_playlist('alice', 'Alice mix')];
  bool authorized = true;

  @override
  List<Playlist> get playlists => serverPlaylists;

  @override
  Stream<List<Playlist>> get playlistsStream => playlistChanges.stream;

  @override
  Stream<AuthState> get authStream => authChanges.stream;

  @override
  AuthState get authState => AuthState(isAuthorized: authorized, baseUrl: 'https://music.test/api');

  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) => null;

  @override
  Track? serverTrackForCurrentServer(Track track) => track;

  @override
  SourceTrackRef? localPlaylistSourceForTrack(Track track) =>
      const SourceTrackRef(serverBaseUrl: 'https://music.test/api', serverTrackId: 'track');

  @override
  Future<Track?> resolveServerTrackForCurrentServer(Track track) async => track;

  @override
  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {}

  @override
  Future<void> removeTrackFromPlaylist(Playlist playlist, Track track) async {}

  @override
  Future<void> close() async {
    await playlistChanges.close();
    await authChanges.close();
  }
}
