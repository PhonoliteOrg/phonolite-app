import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/now_playing_bar.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  for (final presentation in ['desktop', 'compact', 'expanded']) {
    for (final local in [false, true]) {
      for (final empty in [false, true]) {
        final scope = local ? 'local' : 'server';
        testWidgets('$presentation adds to $scope playlists with empty=$empty and opposite shuffle scope', (
          tester,
        ) async {
          final app = _App(local: local, empty: empty);
          final state = _playback(local: local);
          final width = presentation == 'desktop' ? 1280.0 : 390.0;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1000);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            AppScope(
              controller: app,
              child: ObsidianScale(
                scale: ObsidianScale.compute(width),
                child: wrapInTestApp(Align(alignment: Alignment.bottomCenter, child: _player(state, presentation))),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(PlaylistAddIcon));
          await tester.pumpAndSettle();

          expect(find.text('Add to $scope playlist'), findsOneWidget);
          expect(find.text(local ? 'Server mix' : 'Local mix'), findsNothing);
          expect(app.loads, empty ? [scope] : isEmpty);
          final modal = tester.widget<AddToPlaylistModal>(find.byType(AddToPlaylistModal));
          expect(modal.scope, local ? ActionScope.local : ActionScope.server);
          expect(modal.trackId, local ? 'local-track' : 'server-track');

          if (empty) {
            expect(find.text('No $scope playlists available.'), findsOneWidget);
            expect(modal.playlists, isEmpty);
          } else {
            final name = local ? 'Local mix' : 'Server mix';
            expect(find.text(name), findsOneWidget);
            await tester.tap(find.text(name));
            await tester.pumpAndSettle();
            expect(app.additions, ['$scope:mix:${local ? 'local-track' : 'server-track'}']);
            expect(find.byTooltip('Remove from playlist'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  test('offline queue keeps local playlist actions while local playback is starting', () {
    final state = _playback(
      local: false,
    ).copyWith(queueSource: PlaybackQueueSource.offline, shuffleScope: ActionScope.server);
    expect(PlaybackControlsController.actionScopeForPlayback(state), ActionScope.local);
  });
}

PlaybackState _playback({required bool local}) => PlaybackState(
  // A downloaded song can still be streamed from the server.
  track: Track(
    id: 'server-track',
    localId: 'local-track',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    durationMs: 60000,
    liked: false,
    inPlaylists: false,
  ),
  isPlaying: false,
  isLoading: false,
  position: Duration.zero,
  duration: const Duration(minutes: 1),
  bufferRatio: 0,
  volume: 1,
  shuffleMode: ShuffleMode.off,
  shuffleScope: local ? ActionScope.server : ActionScope.local,
  repeatMode: PlaybackRepeatMode.off,
  streamMode: StreamMode.auto,
  bitrateKbps: null,
  streamConnected: !local,
  streamRttMs: null,
  queueSource: PlaybackQueueSource.none,
  queueSourcePlaylistId: null,
  localPlaybackSource: local ? LocalPlaybackSource.library : LocalPlaybackSource.none,
  isLocalPlayback: local,
);

Widget _player(PlaybackState state, String presentation) {
  if (presentation == 'expanded') {
    return NowPlayingExpandedSheet(
      state: state,
      onOpenAlbum: null,
      onPlayPause: () {},
      onNext: () {},
      onPrev: () {},
      onStop: () {},
      onSeek: (_) {},
      onSeekPreview: (_) {},
      onShuffleChanged: (_, {scope}) {},
      onToggleRepeat: () {},
      onStreamModeChanged: (_) {},
      onVolumeChanged: (_) {},
      onToggleMute: () {},
      onToggleLike: () {},
    );
  }
  return NowPlayingBar(
    state: state,
    onOpenAlbum: null,
    onPlayPause: () {},
    onNext: () {},
    onPrev: () {},
    onStop: () {},
    onSeek: (_) {},
    onSeekPreview: (_) {},
    onShuffleChanged: (_, {scope}) {},
    onToggleRepeat: () {},
    onStreamModeChanged: (_) {},
    onVolumeChanged: (_) {},
    onToggleMute: () {},
    onToggleLike: () {},
    compact: presentation == 'compact',
    touchTargets: presentation == 'compact',
  );
}

class _Connection extends Fake implements ServerConnection {
  @override
  int get sessionRevision => 0;
}

class _App extends Fake implements AppController {
  _App({required bool local, required bool empty})
    : playlists = !local && empty ? [] : [Playlist(id: 'mix', name: 'Server mix', trackIds: [])],
      localPlaylists = local && empty ? [] : [Playlist(id: 'mix', name: 'Local mix', trackIds: [])];

  @override
  final catalog = CatalogController(_Connection());
  @override
  final authState = AuthState(isAuthorized: true, baseUrl: 'https://music.test');
  @override
  final List<Playlist> playlists;
  @override
  final List<Playlist> localPlaylists;
  @override
  Map<String, String> get artworkHeaders => const {};

  @override
  Stream<List<Playlist>> get playlistsStream => const Stream.empty();
  @override
  Stream<List<Playlist>> get localPlaylistsStream => const Stream.empty();
  @override
  Stream<AuthState> get authStream => const Stream.empty();

  final loads = <String>[];
  final additions = <String>[];

  @override
  Future<void> loadPlaylists() async => loads.add('server');
  @override
  Future<void> loadLocalPlaylists() async => loads.add('local');
  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) => null;
  @override
  Track? serverTrackForCurrentServer(Track track) => track.copyWith(id: 'server-track');

  @override
  SourceTrackRef? localPlaylistSourceForTrack(Track track) =>
      const SourceTrackRef(serverBaseUrl: 'https://music.test', serverTrackId: 'server-track');

  @override
  Future<String?> resolveLocalPlaylistTrackId(Track track) async => track.localId;

  @override
  Future<Track?> resolveServerTrackForCurrentServer(Track track) async => serverTrackForCurrentServer(track);

  @override
  bool localPlaylistContainsTrack(Playlist playlist, Track track) => playlist.trackIds.contains(track.localId);
  @override
  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async =>
      additions.add('server:${playlist.id}:${track.id}');
  @override
  Future<void> addTrackToLocalPlaylist(Playlist playlist, Track track) async =>
      additions.add('local:${playlist.id}:${track.localId}');
}
