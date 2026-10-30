import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

final _album = Album(id: 'album-1', title: 'Album', artist: 'Artist', artistId: 'artist-1', trackCount: 2);
final _tracks = [
  for (var index = 1; index <= 2; index++)
    offlineTestTrack(id: 'track-$index', title: 'Song $index', albumId: _album.id, album: _album.title),
];

void main() {
  setUpAll(configureTestFonts);

  for (final width in [390.0, 1280.0]) {
    testWidgets('album action follows job-only updates before track transfers at $width', (tester) async {
      final controller = (await tester.runAsync(() async => _AlbumController()))!;

      try {
        await _pump(tester, controller, width: width);
        _expectAction(tester, 'Download Missing', enabled: true);

        for (final (status, label) in [
          (OfflineDownloadStatus.queued, 'Queued'),
          (OfflineDownloadStatus.preparing, 'Preparing'),
          (OfflineDownloadStatus.paused, 'Paused'),
          (OfflineDownloadStatus.failed, 'Retry Downloads'),
          (OfflineDownloadStatus.corrupt, 'Retry Downloads'),
        ]) {
          controller.publish(jobs: [_job(status)]);
          await _pumpUpdates(tester);

          _expectAction(
            tester,
            label,
            enabled: status == OfflineDownloadStatus.failed || status == OfflineDownloadStatus.corrupt,
          );
          expect(controller.downloads, hasLength(1), reason: 'The pending track has not been materialized.');
        }

        controller.publish(
          jobs: [_job(OfflineDownloadStatus.queued)],
          downloads: [
            _download(0),
            _download(1, status: OfflineDownloadStatus.downloading),
          ],
        );
        await _pumpUpdates(tester);
        _expectAction(tester, 'Downloading', enabled: false);

        controller.publish(downloads: [_download(0), _download(1)]);
        await _pumpUpdates(tester);
        _expectAction(tester, 'Downloaded', enabled: false);
        expect(controller.requests, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });
  }

  testWidgets('other albums, servers and finished requests do not block missing album downloads', (tester) async {
    final controller = (await tester.runAsync(() async => _AlbumController()))!;

    try {
      await _pump(tester, controller);

      for (final job in [
        _job(OfflineDownloadStatus.queued, albumId: 'another-album'),
        _job(OfflineDownloadStatus.queued, serverBaseUrl: 'http://another-server.test/api'),
        _job(OfflineDownloadStatus.queued, kind: 'tracks'),
        _job(OfflineDownloadStatus.downloaded),
        _job(OfflineDownloadStatus.canceled),
      ]) {
        controller.publish(jobs: [job]);
        await _pumpUpdates(tester);

        _expectAction(tester, 'Download Missing', enabled: true);
      }

      await tester.tap(_action('Download Missing'));
      await tester.pump();
      expect(controller.requests, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
    }
  });
}

Finder _action(String label) => find.byWidgetPredicate((widget) => widget is TechButton && widget.tooltip == label);

void _expectAction(WidgetTester tester, String label, {required bool enabled}) {
  final action = _action(label);

  expect(action, findsOneWidget);
  expect(tester.widget<TechButton>(action).onTap, enabled ? isNotNull : isNull);
}

Future<void> _pumpUpdates(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pump(WidgetTester tester, _AlbumController controller, {double width = 1280}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: wrapInTestApp(AlbumDetailScreen(album: _album, artistName: _album.artist)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

OfflineDownloadJob _job(
  OfflineDownloadStatus status, {
  String albumId = 'album-1',
  String serverBaseUrl = 'http://server.test/api',
  String kind = 'album',
}) => OfflineDownloadJob(
  jobId: 'opaque-album-request',
  profile: 'opus_128',
  kind: kind,
  sourceId: albumId,
  label: 'An earlier album title',
  serverBaseUrl: serverBaseUrl,
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  totalCount: 1,
);

OfflineTrackDownload _download(int index, {OfflineDownloadStatus status = OfflineDownloadStatus.downloaded}) =>
    offlineTestDownload(serverBaseUrl: 'http://server.test/api', track: _tracks[index], status: status);

class _AlbumController extends AppController {
  List<OfflineTrackDownload> downloads = [_download(0)];
  List<OfflineDownloadJob> jobs = [];
  final snapshots = StreamController<OfflineDownloadSnapshot>.broadcast();
  int requests = 0;

  _AlbumController() : super(connection: _AlbumConnection());

  @override
  List<Track> get tracks => _tracks;

  @override
  Future<void> loadTracks(String albumId) async {}

  @override
  List<OfflineTrackDownload> get offlineDownloads => downloads;

  @override
  List<OfflineDownloadJob> get offlineDownloadJobs => jobs;

  @override
  Stream<List<OfflineTrackDownload>> get offlineDownloadsStream => const Stream.empty();

  @override
  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream => snapshots.stream;

  @override
  OfflineDownloadSnapshot get offlineDownloadSnapshot =>
      OfflineDownloadSnapshot(downloads: downloads, batches: const [], jobs: jobs, revision: 0);

  @override
  OfflineTrackDownload? offlineDownloadForTrack(String trackId) =>
      downloads.where((download) => download.track.id == trackId).firstOrNull;

  @override
  OfflineTrackDownload? availableOfflineDownloadForTrack(String trackId) =>
      downloads.where((download) => download.track.id == trackId && download.isDownloaded).firstOrNull;

  void publish({List<OfflineTrackDownload>? downloads, List<OfflineDownloadJob>? jobs}) {
    this.downloads = downloads ?? this.downloads;
    this.jobs = jobs ?? this.jobs;
    snapshots.add(offlineDownloadSnapshot);
  }

  @override
  Future<void> downloadAlbum(Album album, List<Track> tracks) async {
    expect(album.id, _album.id);
    expect(tracks, _tracks);
    requests++;
  }

  @override
  Future<void> close() async {
    await snapshots.close();
    await super.close();
  }
}

class _AlbumConnection extends ServerConnection {
  _AlbumConnection() : super(baseUrl: 'http://server.test/api');

  @override
  String buildAlbumCoverUrl(String albumId) => '';
}
