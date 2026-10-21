import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_manager_panel.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';

import '../support/widget_test_helpers.dart';

void main() {
  setUpAll(configureTestFonts);
  const unfinishedStates = [
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
    testWidgets(
      'clear all requires work and confirms before clearing at $width',
      (tester) async {
        _setViewport(tester, width);
        final controller = (await tester.runAsync(
          () async => _DownloadActionsController(),
        ))!;
        final job = OfflineDownloadJob(
          jobId: 'job',
          kind: 'artist',
          serverBaseUrl: 'https://unused.test/api/v1',
          status: OfflineDownloadStatus.downloading,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
          totalCount: 1,
          discoveredCount: 1,
        );
        final cases = [
          for (final status in OfflineDownloadStatus.values)
            (
              downloads: [_download(status)],
              jobs: <OfflineDownloadJob>[],
              canClear: status != OfflineDownloadStatus.downloaded,
            ),
          (downloads: <OfflineTrackDownload>[], jobs: [job], canClear: true),
          for (final status in [
            OfflineDownloadStatus.downloaded,
            OfflineDownloadStatus.canceled,
          ])
            (
              downloads: <OfflineTrackDownload>[],
              jobs: [job.copyWith(status: status)],
              canClear: false,
            ),
          (
            downloads: <OfflineTrackDownload>[],
            jobs: <OfflineDownloadJob>[],
            canClear: false,
          ),
        ];
        try {
          for (final entry in cases) {
            await tester.pumpWidget(
              wrapInTestApp(
                DownloadManagerPanel(
                  controller: controller,
                  downloadsOverride: entry.downloads,
                  jobsOverride: entry.jobs,
                ),
              ),
            );
            final clear = find.byTooltip('Clear all jobs and cache');
            final button = tester.widget<TechButton>(
              find.ancestor(of: clear, matching: find.byType(TechButton)),
            );
            expect(button.icon, PhonoliteIcons.listX);
            final previousClears = controller.clears;
            if (!entry.canClear) {
              expect(button.onTap, isNull);
              await tester.tap(clear);
              await tester.pump();
              expect(controller.clears, previousClears);
              expect(find.text('CLEAR'), findsNothing);
              continue;
            }
            expect(button.onTap, isNotNull);
            await tester.tap(clear);
            await tester.pumpAndSettle();
            expect(controller.clears, previousClears);
            expect(
              find.text(
                'Cancel unfinished download jobs and remove their partial files? Successfully downloaded songs will be kept.',
              ),
              findsOneWidget,
            );
            await tester.tap(find.text('CANCEL'));
            await tester.pumpAndSettle();
            expect(controller.clears, previousClears);

            await tester.tap(clear);
            await tester.pumpAndSettle();
            await tester.tap(find.text('CLEAR'));
            await tester.pumpAndSettle();
            expect(controller.clears, previousClears + 1);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(controller.close);
        }
      },
    );

    testWidgets(
      'track tiles offer retry without per-track pause controls at $width',
      (tester) async {
        _setViewport(tester, width);
        final controller = (await tester.runAsync(
          () async => _DownloadActionsController(),
        ))!;
        Offset? actionOffset;
        Size? actionSize;
        try {
          for (final status in unfinishedStates) {
            final download = _download(status);
            final expectedAction = switch (status) {
              OfflineDownloadStatus.failed ||
              OfflineDownloadStatus.corrupt ||
              OfflineDownloadStatus.canceled => 'Retry',
              _ => null,
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
                action == expectedAction && width >= 820
                    ? findsOneWidget
                    : findsNothing,
              );
            }
            expect(find.byTooltip('Remove download'), findsNothing);
            final tile = find.byType(TrackRowTile);
            if (expectedAction == null) {
              expect(
                find.descendant(of: tile, matching: find.byType(IconButton)),
                findsNothing,
              );
              expect(tester.takeException(), isNull);
              continue;
            }
            final transfer = find.byTooltip(
              width < 820 ? 'Track actions' : expectedAction,
            );
            expect(find.ancestor(of: transfer, matching: tile), findsOneWidget);
            expect(
              find.descendant(of: tile, matching: find.byType(IconButton)),
              findsOneWidget,
            );
            final offset =
                tester.getRect(transfer).centerRight -
                tester.getRect(tile).centerRight;
            final size = tester.getSize(transfer);
            actionOffset ??= offset;
            actionSize ??= size;
            expect(offset, actionOffset);
            expect(size, actionSize);
            expect(offset.dx, lessThan(0));
            expect(offset.dy, 0);

            await tester.tap(transfer);
            if (width < 820) {
              await tester.pumpAndSettle();
              expect(find.text('Retry download'), findsOneWidget);
              expect(find.text('Pause'), findsNothing);
              expect(find.text('Delete'), findsNothing);
              await tester.tap(find.text('Retry download'));
              await tester.pumpAndSettle();
            }
            await tester.pump();
            expect(controller.transfers.last.action, expectedAction);
            expect(controller.transfers.last.download, same(download));
            expect(tester.takeException(), isNull);
          }
          expect(controller.transfers, hasLength(3));

          await tester.pumpWidget(
            wrapInTestApp(
              DownloadManagerPanel(
                controller: controller,
                downloadsOverride: [_download(OfflineDownloadStatus.removing)],
                jobsOverride: const [],
              ),
            ),
          );
          expect(find.byTooltip('Pause'), findsNothing);
          expect(find.byTooltip('Resume'), findsNothing);
          expect(
            find.descendant(
              of: find.byType(TrackRowTile),
              matching: find.byType(IconButton),
            ),
            findsNothing,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(controller.close);
        }
      },
    );

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
            await tester.tap(remove);
            await tester.pump();
            expect(controller.removedJobs.last, same(job));
            expect(tester.takeException(), isNull);
          }
        }
        expect(controller.jobTransfers, hasLength(10));
        expect(controller.removedJobs, hasLength(10));
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

  final removedJobs = <OfflineDownloadJob>[];
  final transfers = <({String action, OfflineTrackDownload download})>[];
  final jobTransfers = <({String action, OfflineDownloadJob job})>[];
  int clears = 0;

  @override
  Future<void> clearUnfinishedOfflineDownloads() async {
    clears++;
  }

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
  Future<void> cancelOfflineDownloadJob(OfflineDownloadJob job) async {
    removedJobs.add(job);
  }
}
