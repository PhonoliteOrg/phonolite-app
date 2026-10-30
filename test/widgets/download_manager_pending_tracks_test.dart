import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/catalog_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_manager_panel.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';

import '../support/widget_test_helpers.dart';

const _server = 'https://downloads.test/api';
final _now = DateTime.utc(2026);

void main() {
  setUpAll(configureTestFonts);

  for (final width in [390.0, 1280.0]) {
    testWidgets('queued tracks appear on snapshot updates before transfer files exist at $width', (tester) async {
      _setViewport(tester, width);
      final job = _job();
      final controller = _SnapshotController(_snapshot(jobs: [job]));
      addTearDown(controller.snapshots.close);

      await tester.pumpWidget(wrapInTestApp(DownloadManagerPanel(controller: controller)));
      expect(find.byType(TrackRowTile), findsNothing);

      final item = _item(0);
      controller.publish(_snapshot(jobs: [job], items: [item], revision: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      var tile = tester.widget<TrackRowTile>(_track('song-0'));
      expect(tile.downloadStatus, OfflineDownloadStatus.queued);
      expect(tile.offlineDownload, isNull);
      expect(find.byTooltip('Retry'), findsNothing);

      final transfer = OfflineTrackDownload(
        serverBaseUrl: _server,
        track: item.track!,
        status: OfflineDownloadStatus.downloading,
        createdAt: _now,
        updatedAt: _now,
        bytesDownloaded: 20,
        bytesTotal: 100,
      );
      controller.publish(_snapshot(jobs: [job], items: [item], downloads: [transfer], revision: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_track('song-0'), findsOneWidget);
      tile = tester.widget<TrackRowTile>(_track('song-0'));
      expect(tile.offlineDownload, same(transfer));

      controller.publish(
        _snapshot(
          jobs: [job],
          items: [item],
          downloads: [transfer.copyWith(status: OfflineDownloadStatus.downloaded)],
          revision: 4,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_track('song-0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tracks outside the transfer window stay reachable in the queue at $width', (tester) async {
      _setViewport(tester, width);
      await tester.pumpWidget(
        wrapInTestApp(
          DownloadManagerPanel(
            downloadsOverride: const [],
            jobsOverride: [_job()],
            jobItemsOverride: [for (var position = 0; position < 25; position++) _item(position)],
          ),
        ),
      );

      await tester.scrollUntilVisible(_track('song-24'), 350, scrollable: find.byType(Scrollable).first);

      final tile = tester.widget<TrackRowTile>(_track('song-24'));
      expect(tile.track.title, 'Song 25');
      expect(tile.downloadStatus, OfflineDownloadStatus.queued);
      expect(tile.offlineDownload, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}

void _setViewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Finder _track(String id) => find.byWidgetPredicate((widget) => widget is TrackRowTile && widget.track.id == id);

OfflineDownloadJob _job() => OfflineDownloadJob(
  jobId: 'album-job',
  kind: 'album',
  profile: 'opus_128',
  label: 'Album download',
  serverBaseUrl: _server,
  status: OfflineDownloadStatus.queued,
  totalCount: 25,
  discoveredCount: 25,
  createdAt: _now,
  updatedAt: _now,
);

OfflineDownloadJobItem _item(int position) => OfflineDownloadJobItem(
  jobId: 'album-job',
  position: position,
  serverTrackId: 'song-$position',
  status: OfflineDownloadStatus.queued,
  materialized: false,
  createdAt: _now,
  updatedAt: _now,
  track: Track(
    id: 'song-$position',
    title: 'Song ${position + 1}',
    artist: 'Artist',
    album: 'Album',
    durationMs: 60000,
    liked: false,
    inPlaylists: false,
  ),
);

OfflineDownloadSnapshot _snapshot({
  List<OfflineDownloadJob> jobs = const [],
  List<OfflineDownloadJobItem> items = const [],
  List<OfflineTrackDownload> downloads = const [],
  int revision = 1,
}) => OfflineDownloadSnapshot(downloads: downloads, batches: const [], jobs: jobs, jobItems: items, revision: revision);

class _SnapshotController extends Fake implements AppController {
  final snapshots = StreamController<OfflineDownloadSnapshot>.broadcast();
  OfflineDownloadSnapshot _snapshot;

  _SnapshotController(this._snapshot);

  @override
  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream => snapshots.stream;

  @override
  OfflineDownloadSnapshot get offlineDownloadSnapshot => _snapshot;

  @override
  CatalogController get catalog => _Catalog();

  @override
  Map<String, String> get artworkHeaders => const {};

  void publish(OfflineDownloadSnapshot snapshot) {
    _snapshot = snapshot;
    snapshots.add(snapshot);
  }
}

class _Catalog extends Fake implements CatalogController {
  @override
  String get baseUrl => _server;
}
