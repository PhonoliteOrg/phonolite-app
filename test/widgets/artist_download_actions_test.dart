import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_models.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/pages/artist_detail_screen.dart';
import 'package:phonolite_app/widgets/layouts/app_scope.dart';
import 'package:phonolite_app/widgets/ui/tech_button.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

final _artist = Artist(id: 'artist-1', name: 'Artist', albumCount: 3);
final _albums = [
  for (var index = 1; index <= 3; index++)
    Album(
      id: 'album-$index',
      title: 'Album $index',
      artist: _artist.name,
      artistId: _artist.id,
      trackCount: 2,
    ),
];

void main() {
  setUpAll(configureTestFonts);

  for (final width in [390.0, 1280.0]) {
    for (final queuedAlbums in [1, 2]) {
      testWidgets(
        'artist can queue missing albums with $queuedAlbums albums queued at $width',
        (tester) async {
          final controller = (await tester.runAsync(
            () async => _ArtistController(
              downloads: _downloads(queuedAlbums, OfflineDownloadStatus.queued),
            ),
          ))!;
          try {
            await _pump(tester, controller, width: width);
            final button = _button('Download Missing');
            expect(tester.widget<TechButton>(button).onTap, isNotNull);
            await tester.tap(button);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(controller.requests, isEmpty);
            await tester.tap(find.text('DOWNLOAD'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(controller.requests.single, _albums);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(controller.close);
          }
        },
      );
    }
  }

  for (final status in [
    OfflineDownloadStatus.preparing,
    OfflineDownloadStatus.paused,
  ]) {
    testWidgets('existing $status artist job blocks a duplicate request', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () async => _ArtistController(
          jobs: [
            OfflineDownloadJob(
              jobId: 'opaque-job-id',
              kind: 'artist',
              sourceId: _artist.id,
              label: 'An earlier artist name',
              serverBaseUrl: 'http://server.test/api/v1',
              status: status,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              totalCount: 6,
            ),
          ],
        ),
      ))!;
      try {
        await _pump(tester, controller);
        expect(tester.widget<TechButton>(_button('Downloading')).onTap, isNull);
        expect(controller.requests, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });
  }

  for (final status in [
    OfflineDownloadStatus.queued,
    OfflineDownloadStatus.downloaded,
  ]) {
    testWidgets('artist request is disabled when all tracks are $status', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () async => _ArtistController(downloads: _downloads(3, status)),
      ))!;
      try {
        await _pump(tester, controller);
        final label = status == OfflineDownloadStatus.downloaded
            ? 'Downloaded'
            : 'Downloading';
        expect(tester.widget<TechButton>(_button(label)).onTap, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });
  }
}

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is TechButton && widget.tooltip == label,
);

Future<void> _pump(
  WidgetTester tester,
  _ArtistController controller, {
  double width = 1280,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: wrapInTestApp(ArtistDetailScreen(artist: _artist)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

List<OfflineTrackDownload> _downloads(
  int albumCount,
  OfflineDownloadStatus status,
) => [
  for (final album in _albums.take(albumCount))
    for (var index = 1; index <= album.trackCount; index++)
      offlineTestDownload(
        serverBaseUrl: 'http://server.test/api/v1',
        track: offlineTestTrack(
          id: '${album.id}-track-$index',
          artist: _artist.name,
          albumId: album.id,
          album: album.title,
        ),
        status: status,
      ),
];

class _ArtistController extends AppController {
  _ArtistController({this.downloads = const [], this.jobs = const []})
    : super(connection: _ArtistConnection());

  final List<OfflineTrackDownload> downloads;
  final List<OfflineDownloadJob> jobs;
  final requests = <List<Album>>[];

  @override
  ArtistReleases get artistReleases => ArtistReleases(albums: _albums);
  @override
  Future<void> loadArtistReleases(String artistId) async {}
  @override
  List<OfflineTrackDownload> get offlineDownloads => downloads;
  @override
  List<OfflineDownloadJob> get offlineDownloadJobs => jobs;
  @override
  OfflineDownloadSnapshot get offlineDownloadSnapshot =>
      OfflineDownloadSnapshot(
        downloads: downloads,
        batches: const [],
        jobs: jobs,
        revision: 0,
      );
  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) {
    for (final download in downloads) {
      if (download.track.id == trackId && download.isDownloaded) {
        return download;
      }
    }
    return null;
  }

  @override
  Future<void> downloadArtist(Artist artist, List<Album> albums) async {
    expect(artist.id, _artist.id);
    requests.add(albums);
  }
}

class _ArtistConnection extends ServerConnection {
  _ArtistConnection() : super(baseUrl: 'http://server.test/api/v1');

  @override
  Future<Artist> fetchArtistById(String artistId) async => _artist;
  @override
  String buildAlbumCoverUrl(String albumId) => '';
}
