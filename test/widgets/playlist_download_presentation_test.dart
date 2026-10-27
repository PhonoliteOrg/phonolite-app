import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_track_actions.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);

  testWidgets('local addition becomes normal membership only after persistence succeeds', (tester) async {
    final saved = Completer<void>();
    await tester.pumpWidget(
      wrapInTestApp(
        AddToPlaylistModal(
          scope: ActionScope.local,
          playlists: [_playlist('Local mix')],
          trackId: 'source-track',
          canUsePlaylists: true,
          onSelected: (_) => saved.future,
          onRemoved: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Local mix'));
    await tester.pump();
    expect(find.byTooltip('Remove from playlist'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    saved.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove from playlist'), findsOneWidget);
    expect(find.text('Local - 1 tracks'), findsOneWidget);
    expect(find.textContaining('Downloading'), findsNothing);
    expect(find.textContaining('Queued'), findsNothing);
  });

  testWidgets('failed persistence does not show a saved playlist membership', (tester) async {
    await tester.pumpWidget(
      wrapInTestApp(
        AddToPlaylistModal(
          scope: ActionScope.local,
          playlists: [_playlist('Local mix')],
          trackId: 'source-track',
          canUsePlaylists: true,
          onSelected: (_) => Future<void>.error(StateError('disk full')),
          onRemoved: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Local mix'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to playlist'), findsOneWidget);
    expect(find.byTooltip('Remove from playlist'), findsNothing);
    expect(find.text('Local - 0 tracks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scope switching preserves search and pending membership without modal download status', (tester) async {
    const source = SourceTrackRef(serverBaseUrl: 'https://music.test/api', serverTrackId: 'source-track');
    final local = _playlist('Local mix').copyWith(pendingTrackSources: [source]);
    final server = _playlist('Server mix');
    await tester.pumpWidget(
      wrapInTestApp(
        AddToPlaylistModal(
          scope: ActionScope.server,
          playlists: [server],
          trackId: source.serverTrackId,
          canUsePlaylists: true,
          onSelected: (_) {},
          onRemoved: (_) {},
          actionsForScope: (scope) async => PlaylistTrackActions(
            playlists: [scope == ActionScope.local ? local : server],
            trackId: source.serverTrackId,
            canUsePlaylists: true,
            add: (_) {},
            remove: (_) {},
            containsTrack: (playlist) => playlist.pendingTrackSources.contains(source),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'mix');
    await tester.tap(find.text('LOCAL'));
    await tester.pumpAndSettle();
    expect(find.text('Add to local playlist'), findsOneWidget);
    expect(find.text('Local mix'), findsOneWidget);
    expect(find.text('Server mix'), findsNothing);
    expect(find.text('Local - 1 tracks'), findsOneWidget);
    expect(find.byTooltip('Remove from playlist'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'mix');

    await tester.tap(find.text('SERVER'));
    await tester.pumpAndSettle();
    expect(find.text('Server - 0 tracks'), findsOneWidget);
    expect(find.byTooltip('Add to playlist'), findsOneWidget);
    expect(find.textContaining('Download'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a failed pending addition shows only normal saved membership', (tester) async {
    const source = SourceTrackRef(serverBaseUrl: 'https://music.test/api', serverTrackId: 'source-track');
    final saved = _playlist('Local mix').copyWith(pendingTrackSources: [source]);

    Widget modal() => wrapInTestApp(
      AddToPlaylistModal(
        scope: ActionScope.local,
        playlists: [saved],
        trackId: source.serverTrackId,
        canUsePlaylists: true,
        containsTrack: (playlist) => playlist.pendingTrackSources.contains(source),
        onSelected: (_) {},
        onRemoved: (_) {},
      ),
    );

    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove from playlist'), findsOneWidget);
    expect(find.text('Local - 1 tracks'), findsOneWidget);
    expect(find.textContaining('Download'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('long track title and failure status keep the existing row height at large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final track = _track().copyWith(title: 'A very long track title with several edition and recording credits');

    Future<void> pumpRow(OfflineDownloadStatus? status) async {
      await tester.pumpWidget(
        wrapInTestApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.8)),
              child: TrackRowTile(
                track: track,
                index: 1,
                downloadStatus: status,
                onDownload: () {},
                onRetryDownload: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpRow(null);
    final height = tester.getSize(find.byType(TrackRowTile)).height;
    await pumpRow(OfflineDownloadStatus.failed);
    expect(tester.getSize(find.byType(TrackRowTile)).height, height);
    expect(find.text('Artist / Album'), findsOneWidget);
    expect(find.text(' · Download failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final status in [OfflineDownloadStatus.failed, OfflineDownloadStatus.paused]) {
    testWidgets('track title and existing action reflect $status without changing subtitle', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var retries = 0;
      var continuations = 0;
      final track = _track();
      await tester.pumpWidget(
        wrapInTestApp(
          TrackRowTile(
            track: track,
            index: 1,
            downloadStatus: status,
            onRetryDownload: () => retries++,
            onContinueDownload: () => continuations++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Artist / Album'), findsOneWidget);
      expect(track.title, 'Song');
      expect(find.text(status == OfflineDownloadStatus.failed ? ' · Download failed' : ' · Paused'), findsOneWidget);
      final action = status == OfflineDownloadStatus.failed ? 'Retry download' : 'Continue download';
      await tester.tap(find.byTooltip(action));
      await tester.pump();
      expect(retries, status == OfflineDownloadStatus.failed ? 1 : 0);
      expect(continuations, status == OfflineDownloadStatus.paused ? 1 : 0);
      expect(find.byType(ReloadIcon), status == OfflineDownloadStatus.failed ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Playlist _playlist(String name) => Playlist(id: 'same-id', name: name, trackIds: []);

Track _track() => Track(
  id: 'source-track',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  durationMs: 180000,
  liked: false,
  inPlaylists: false,
);
