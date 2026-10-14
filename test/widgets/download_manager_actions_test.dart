import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/app_controller.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_models.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/widgets/display/album_row_tile.dart';
import 'package:phonolite_app/widgets/display/artist_row_tile.dart';
import 'package:phonolite_app/widgets/display/track_row_tile.dart';
import 'package:phonolite_app/widgets/modals/download_manager_panel.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);
  const removableStates = [
    OfflineDownloadStatus.queued,
    OfflineDownloadStatus.preparing,
    OfflineDownloadStatus.downloading,
    OfflineDownloadStatus.validating,
    OfflineDownloadStatus.paused,
    OfflineDownloadStatus.failed,
    OfflineDownloadStatus.corrupt,
    OfflineDownloadStatus.canceled,
  ];

  for (final width in [390.0, 1280.0]) {
    testWidgets('one Remove action handles unfinished downloads at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = (await tester.runAsync(
        () async => _DownloadActionsController(),
      ))!;
      try {
        for (final status in removableStates) {
          final download = _download(status);
          await tester.pumpWidget(
            wrapInTestApp(
              DownloadManagerPanel(
                controller: controller,
                downloadsOverride: [download],
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byTooltip('Cancel'), findsNothing);
          expect(find.byTooltip('Remove partial cache'), findsNothing);
          final remove = find.byTooltip('Remove download');
          expect(remove, findsOneWidget);
          await tester.tap(remove);
          await tester.pump();
          expect(controller.removed.last, same(download));
          expect(controller.cancels, 0);
          expect(tester.takeException(), isNull);
        }
        expect(controller.removed, hasLength(removableStates.length));

        await tester.pumpWidget(
          wrapInTestApp(
            DownloadManagerPanel(
              controller: controller,
              downloadsOverride: [_download(OfflineDownloadStatus.removing)],
            ),
          ),
        );
        final remove = find.byTooltip('Remove download');
        final button = find.descendant(
          of: remove,
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(button).onPressed, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });

    testWidgets('transfer action changes in one fixed slot at $width', (
      tester,
    ) async {
      _setViewport(tester, width);
      final controller = (await tester.runAsync(
        () async => _DownloadActionsController(),
      ))!;
      Offset? actionOffset;
      Size? actionSize;
      try {
        for (final status in removableStates) {
          final download = _download(status);
          final expectedAction = switch (status) {
            OfflineDownloadStatus.paused => 'Resume',
            OfflineDownloadStatus.failed ||
            OfflineDownloadStatus.corrupt ||
            OfflineDownloadStatus.canceled => 'Retry',
            _ => 'Pause',
          };
          await tester.pumpWidget(
            wrapInTestApp(
              DownloadManagerPanel(
                controller: controller,
                downloadsOverride: [download],
                jobsOverride: const [],
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));

          for (final action in ['Pause', 'Resume', 'Retry']) {
            expect(
              find.byTooltip(action),
              action == expectedAction ? findsOneWidget : findsNothing,
            );
          }
          final transfer = find.byTooltip(expectedAction);
          final remove = find.byTooltip('Remove download');
          expect(
            find.ancestor(of: transfer, matching: find.byType(TrackRowTile)),
            findsOneWidget,
          );
          expect(
            find.ancestor(of: remove, matching: find.byType(TrackRowTile)),
            findsOneWidget,
          );
          final offset =
              tester.getTopLeft(transfer) - tester.getTopLeft(remove);
          final size = tester.getSize(transfer);
          actionOffset ??= offset;
          actionSize ??= size;
          expect(offset, actionOffset);
          expect(size, actionSize);
          expect(size, tester.getSize(remove));
          expect(offset.dx, lessThan(0));
          expect(offset.dy, 0);

          await tester.tap(transfer);
          await tester.pump();
          expect(controller.transfers.last.action, expectedAction);
          expect(controller.transfers.last.download, same(download));
          expect(tester.takeException(), isNull);
        }
        expect(controller.transfers, hasLength(removableStates.length));

        await tester.pumpWidget(
          wrapInTestApp(
            DownloadManagerPanel(
              controller: controller,
              downloadsOverride: [_download(OfflineDownloadStatus.removing)],
              jobsOverride: const [],
            ),
          ),
        );
        final pause = find.descendant(
          of: find.byTooltip('Pause'),
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(pause).onPressed, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
    });

    testWidgets('job pause and resume share one fixed slot at $width', (
      tester,
    ) async {
      _setViewport(tester, width);
      final controller = (await tester.runAsync(
        () async => _DownloadActionsController(),
      ))!;
      Offset? actionOffset;
      try {
        for (final kind in ['album', 'artist']) {
          for (final status in [
            OfflineDownloadStatus.queued,
            OfflineDownloadStatus.preparing,
            OfflineDownloadStatus.downloading,
            OfflineDownloadStatus.validating,
            OfflineDownloadStatus.paused,
          ]) {
            final job = OfflineDownloadJob(
              jobId: 'job',
              kind: kind,
              serverBaseUrl: 'https://unused.test/api/v1',
              status: status,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
              totalCount: 1,
              discoveredCount: 1,
            );
            final expectedAction = status == OfflineDownloadStatus.paused
                ? 'Resume'
                : 'Pause';
            final otherAction = expectedAction == 'Pause' ? 'Resume' : 'Pause';
            await tester.pumpWidget(
              wrapInTestApp(
                DownloadManagerPanel(
                  controller: controller,
                  downloadsOverride: const [],
                  jobsOverride: [job],
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 250));

            final transfer = find.byTooltip('$expectedAction download job');
            final remove = find.byTooltip('Cancel and remove job');
            expect(transfer, findsOneWidget);
            expect(find.byTooltip('$otherAction download job'), findsNothing);
            final tile = find.byType(
              kind == 'album' ? AlbumRowTile : ArtistRowTile,
            );
            expect(find.ancestor(of: transfer, matching: tile), findsOneWidget);
            expect(find.ancestor(of: remove, matching: tile), findsOneWidget);
            final offset =
                tester.getTopLeft(transfer) - tester.getTopLeft(remove);
            actionOffset ??= offset;
            expect(offset, actionOffset);
            expect(tester.getSize(transfer), tester.getSize(remove));
            expect(offset.dx, lessThan(0));
            expect(offset.dy, 0);

            await tester.tap(transfer);
            await tester.pump();
            expect(controller.jobTransfers.last.action, expectedAction);
            expect(controller.jobTransfers.last.job, same(job));
            expect(tester.takeException(), isNull);
          }
        }
        expect(controller.jobTransfers, hasLength(10));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
      }
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

OfflineTrackDownload _download(OfflineDownloadStatus status) =>
    OfflineTrackDownload(
      serverBaseUrl: 'https://unused.test/api/v1',
      track: Track(
        id: 'track',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 60000,
        liked: false,
        inPlaylists: false,
      ),
      status: status,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      bytesDownloaded: 25,
      bytesTotal: 100,
    );

class _DownloadActionsController extends AppController {
  _DownloadActionsController()
    : super(
        connection: ServerConnection(baseUrl: 'https://unused.test/api/v1'),
      );

  final removed = <OfflineTrackDownload>[];
  final transfers = <({String action, OfflineTrackDownload download})>[];
  final jobTransfers = <({String action, OfflineDownloadJob job})>[];
  int cancels = 0;

  @override
  Future<void> pauseOfflineDownload(OfflineTrackDownload download) async {
    transfers.add((action: 'Pause', download: download));
  }

  @override
  Future<void> resumeOfflineDownload(OfflineTrackDownload download) async {
    transfers.add((action: 'Resume', download: download));
  }

  @override
  Future<void> retryOfflineDownload(OfflineTrackDownload download) async {
    transfers.add((action: 'Retry', download: download));
  }

  @override
  Future<void> pauseOfflineDownloadJob(OfflineDownloadJob job) async {
    jobTransfers.add((action: 'Pause', job: job));
  }

  @override
  Future<void> resumeOfflineDownloadJob(OfflineDownloadJob job) async {
    jobTransfers.add((action: 'Resume', job: job));
  }

  @override
  Future<void> removeOfflineDownload(OfflineTrackDownload download) async {
    removed.add(download);
  }

  @override
  Future<void> cancelOfflineDownload(OfflineTrackDownload download) async {
    cancels++;
  }
}
