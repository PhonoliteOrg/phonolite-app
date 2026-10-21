import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/pages/library/artist_detail_screen.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';

import '../support/offline_library_test_helpers.dart';
import '../support/widget_test_helpers.dart';

const _server = 'https://deletion.test:3000/api/v1';
final _artist = Artist(id: 'artist-1', name: 'The Artist', albumCount: 1);
final _album = Album(
  id: 'album-1',
  title: 'The Album',
  artist: _artist.name,
  artistId: _artist.id,
  trackCount: 4,
);

class _Connection extends ServerConnection {
  _Connection()
    : super(
        baseUrl: _server,
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );

  @override
  Future<Artist> fetchArtistById(String artistId) async => _artist;

  @override
  String buildAlbumCoverUrl(String albumId) => '';
}

class _GatedConnection extends _Connection {
  final requested = Completer<void>();
  final responseReady = Completer<void>();

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    requested.complete();
    await responseReady.future;
    // Exercise metadata staging without starting any media worker.
    setToken(null);
    return offlineTestDownloadManifest(
      batchId: clientBatchId!,
      trackId: trackIds.single,
    );
  }
}

class _Controller extends AppController {
  _Controller(this.manager, this.storage)
    : super(
        connection: _Connection(),
        offlineDownloadManager: manager,
        offlineStorage: storage,
      );

  final OfflineDownloadManager manager;
  final OfflineLibraryStorage storage;

  @override
  Future<void> loadArtistReleases(String artistId) async {}

  @override
  ArtistReleases get artistReleases => ArtistReleases(albums: [_album]);

  @override
  Stream<OfflineDownloadSnapshot> get offlineDownloadSnapshotStream =>
      manager.stream.map((_) => manager.downloadSnapshot);
}

Future<void> _seedArtist(
  OfflineLibraryStorage storage,
  Directory root, {
  String server = _server,
  String artistId = 'artist-1',
  String name = 'The Artist',
  String jobId = 'artist-job',
  String albumId = 'album-1',
}) async {
  final now = DateTime.now();
  Track track(String id) => offlineTestTrack(
    id: '$jobId-$id',
    title: '$jobId-$id',
    artist: name,
    artistId: artistId,
    albumId: albumId,
    album: albumId,
  );
  final file = await offlineTestMediaFile(root, '$jobId.mp3');
  await storage.upsertDownloads(
    await storage.prepareDownloads([
      offlineTestDownload(
        serverBaseUrl: server,
        batchId: jobId,
        track: track('done'),
        filePath: file.path,
      ),
      offlineTestDownload(
        serverBaseUrl: server,
        batchId: jobId,
        track: track('failed'),
        status: OfflineDownloadStatus.failed,
      ),
    ]),
  );
  await storage.saveDownloadPlan(
    job: OfflineDownloadJob(
      jobId: jobId,
      kind: 'artist',
      serverBaseUrl: server,
      sourceId: artistId,
      label: name,
      status: OfflineDownloadStatus.failed,
      createdAt: now,
      updatedAt: now,
      totalCount: 4,
    ),
    batch: OfflineDownloadBatch(
      batchId: jobId,
      serverBaseUrl: server,
      totalCount: 4,
      status: OfflineDownloadStatus.failed,
      createdAt: now,
      updatedAt: now,
    ),
    items: [
      for (var index = 0; index < 3; index++)
        OfflineDownloadJobItem(
          jobId: jobId,
          position: index,
          serverTrackId: track(['done', 'failed', 'unstaged'][index]).id,
          track: track(['done', 'failed', 'unstaged'][index]),
          status: index == 0
              ? OfflineDownloadStatus.downloaded
              : OfflineDownloadStatus.failed,
          materialized: index < 2,
          createdAt: now,
          updatedAt: now,
        ),
    ],
    sources: [
      OfflineDownloadJobSource(
        jobId: jobId,
        position: 0,
        sourceId: albumId,
        status: OfflineDownloadStatus.failed,
        createdAt: now,
        updatedAt: now,
        error: 'Album lookup interrupted',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(configureTestFonts);

  for (final keepPlan in [true, false]) {
    testWidgets(
      'deleting a downloaded artist resets Retry Downloads and stays reset (saved plan: $keepPlan)',
      (tester) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('phonolite_artist_delete_'),
        ))!;
        final controller = (await tester.runAsync(() async {
          final storage = OfflineLibraryStorage(baseDirectory: root);
          final manager = OfflineDownloadManager(
            connection: _Connection(),
            storage: storage,
          );
          await _seedArtist(storage, root);
          if (!keepPlan) await storage.deleteDownloadJob('artist-job');
          await manager.load();
          return _Controller(manager, storage);
        }))!;
        final storage = controller.storage;
        final manager = controller.manager;
        try {
          await tester.pumpWidget(
            AppScope(
              controller: controller,
              child: wrapInTestApp(ArtistDetailScreen(artist: _artist)),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TechButton && widget.label == 'Retry Downloads',
            ),
            findsOneWidget,
          );

          await tester.runAsync(() async {
            // This is the library's deletion path: its selection contains only
            // downloaded tracks, not failed rows or undiscovered albums.
            await controller.removeDownloadedTracks(
              controller.offlineTracks,
              scope: OfflineDeletionScope.artist(
                id: _artist.id,
                label: _artist.name,
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 120));
          });
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TechButton && widget.label == 'Download Artist',
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TechButton && widget.label == 'Retry Downloads',
            ),
            findsNothing,
          );
          expect(manager.downloads, isEmpty);
          expect(manager.jobs, isEmpty);
          await tester.runAsync(() async {
            expect(await storage.readDownloadJobs(), isEmpty);
            expect(await storage.readDownloadJobItems('artist-job'), isEmpty);
            expect(await storage.readDownloadJobSources('artist-job'), isEmpty);
            expect(await storage.readDownloadBatches(), isEmpty);
            await manager.load();
            expect(manager.jobs, isEmpty);
            expect(manager.downloads, isEmpty);
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await controller.close();
            await root.delete(recursive: true);
          });
        }
      },
    );
  }

  test('a late staging response cannot recreate a deleted artist', () async {
    final root = await Directory.systemTemp.createTemp(
      'phonolite_artist_delete_race_',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = OfflineLibraryStorage(baseDirectory: root);
    await _seedArtist(storage, root);
    final failed = (await storage.readDownloads()).singleWhere(
      (download) => !download.isDownloaded,
    );
    await storage.removeDownloads([failed]);
    final job = (await storage.readDownloadJobs()).single;
    await storage.upsertDownloadJob(
      job.copyWith(status: OfflineDownloadStatus.queued),
    );
    await storage.upsertDownloadJobItems([
      for (final item in await storage.readDownloadJobItems(job.jobId))
        if (!item.materialized)
          item.copyWith(status: OfflineDownloadStatus.queued),
    ]);
    await storage.upsertDownloadJobSources([
      for (final source in await storage.readDownloadJobSources(job.jobId))
        source.copyWith(status: OfflineDownloadStatus.downloaded),
    ]);
    final connection = _GatedConnection()..setToken('session');
    final manager = OfflineDownloadManager(
      connection: connection,
      storage: storage,
    );
    try {
      await manager.load();
      await connection.requested.future;
      await manager.removeDownloads(
        manager.downloads.where((download) => download.isDownloaded),
        scope: OfflineDeletionScope.artist(id: _artist.id, label: _artist.name),
      );
    } finally {
      connection.responseReady.complete();
      await manager.dispose();
    }
    expect(manager.jobs, isEmpty);
    expect(manager.downloads, isEmpty);
    expect(await storage.readDownloads(), isEmpty);
    expect(await storage.readDownloadJobs(), isEmpty);
    await storage.close();
    final restored = OfflineDownloadManager(
      connection: _Connection(),
      storage: OfflineLibraryStorage(baseDirectory: root),
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.downloads, isEmpty);
    expect(restored.jobs, isEmpty);
  });

  test(
    'bulk artist deletion clears only selected artists on selected servers',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_bulk_delete_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      await _seedArtist(storage, root);
      await _seedArtist(
        storage,
        root,
        artistId: 'artist-2',
        name: 'Second Artist',
        jobId: 'second-job',
        albumId: 'second-album',
      );
      await _seedArtist(
        storage,
        root,
        artistId: 'unselected',
        name: 'The Artist',
        jobId: 'unselected-job',
        albumId: 'unselected-album',
      );
      await _seedArtist(
        storage,
        root,
        server: 'https://other.test/api/v1',
        jobId: 'other-server-job',
      );
      final manager = OfflineDownloadManager(
        connection: _Connection(),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      await manager.removeDownloads(
        manager.downloads.where(
          (download) =>
              download.isDownloaded &&
              download.serverBaseUrl == _server &&
              download.track.artistId != 'unselected',
        ),
        scope: const OfflineDeletionScope.artist(ids: ['artist-1', 'artist-2']),
      );
      expect(manager.jobs.map((job) => job.jobId).toSet(), {
        'unselected-job',
        'other-server-job',
      });
      expect(manager.downloads, hasLength(4));
      expect(
        (await storage.readDownloadJobs()).map((job) => job.jobId).toSet(),
        {'unselected-job', 'other-server-job'},
      );
      expect(await storage.readDownloadJobItems('artist-job'), isEmpty);
      expect(await storage.readDownloadJobSources('second-job'), isEmpty);
    },
  );
}
