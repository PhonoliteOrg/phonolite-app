import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _server = 'https://reset.test:3000/api/v1';

class _Connection extends ServerConnection {
  _Connection()
    : super(
        baseUrl: _server,
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<ServerArtwork?> fetchAlbumCoverBytes(
    String albumId, {
    Duration? timeout,
  }) async => null;

  @override
  Future<ServerArtwork?> fetchArtistCoverBytes(
    String artistId, {
    String kind = 'logo',
    Duration? timeout,
  }) async => null;
}

class _PendingV2Connection extends _Connection {
  final requested = Completer<void>();
  final response = Completer<DownloadJobV2>();

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: true,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) async {
    requested.complete();
    final job = await response.future;
    setToken(null);
    return job;
  }
}

class _PendingMetadataConnection extends _Connection {
  final requested = Completer<void>();
  final response = Completer<OfflineTrackMetadata>();

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    if (!requested.isCompleted) requested.complete();
    return response.future;
  }
}

class _PreparingStorage extends OfflineLibraryStorage {
  _PreparingStorage(Directory root) : super(baseDirectory: root);
  final preparing = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<File> partialTrackFile({
    required String serverBaseUrl,
    required String trackId,
  }) async {
    preparing.complete();
    await proceed.future;
    return super.partialTrackFile(
      serverBaseUrl: serverBaseUrl,
      trackId: trackId,
    );
  }
}

class _SavingPlanStorage extends OfflineLibraryStorage {
  _SavingPlanStorage(Directory root) : super(baseDirectory: root);
  final saving = Completer<void>();
  final proceed = Completer<void>();

  @override
  Future<void> saveDownloadPlan({
    required OfflineDownloadJob job,
    required OfflineDownloadBatch batch,
    List<OfflineDownloadJobItem> items = const [],
    List<OfflineDownloadJobSource> sources = const [],
  }) async {
    saving.complete();
    await proceed.future;
    await super.saveDownloadPlan(
      job: job,
      batch: batch,
      items: items,
      sources: sources,
    );
  }
}

Future<void> _saveCompleted(
  OfflineLibraryStorage storage, {
  String title = 'Song',
  bool metadata = false,
}) async {
  final file = await storage.trackFile(serverBaseUrl: _server, trackId: 'song');
  await file.writeAsBytes([1, 2, 3]);
  final snapshot = offlineTestOfflineMetadata(
    trackId: 'song',
    trackTitle: title,
  );
  await storage.upsertDownload(
    await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: _server,
        track: snapshot.track,
        filePath: file.path,
      ).copyWith(offlineMetadata: metadata ? snapshot : null),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final unfinishedOnly in [false, true]) {
    test(
      '${unfinishedOnly ? 'cache clear preserves completed downloads' : 'full reset clears all downloads'} across restart',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'phonolite_reset_states_',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: root);
        final playlist = await storage.createLocalPlaylist(
          'Keep this playlist',
        );
        final playlistWithImage = (await storage.updateLocalPlaylistImage(
          playlist.id,
          PlaylistImageEdit.replace(
            bytes: Uint8List.fromList([1, 2, 3]),
            contentType: 'image/png',
          ),
        ))!;
        final now = DateTime.now();
        final oldClientId = await storage.readOrCreateClientId();
        final files = <OfflineDownloadStatus, File>{};
        for (final status in OfflineDownloadStatus.values) {
          final id = status.name;
          final file = await storage.partialTrackFile(
            serverBaseUrl: _server,
            trackId: id,
          );
          await file.writeAsBytes([1, 2, 3]);
          files[status] = file;
          await storage.upsertDownload(
            await storage.prepareDownload(
              offlineTestDownload(
                serverBaseUrl: _server,
                batchId: id,
                track: offlineTestTrack(id: id, title: id),
                status: status,
                filePath: status == OfflineDownloadStatus.downloaded
                    ? file.path
                    : null,
              ).copyWith(partialPath: file.path),
            ),
          );
          await storage.saveDownloadPlan(
            job: OfflineDownloadJob(
              jobId: id,
              kind: 'artist',
              serverBaseUrl: _server,
              status: status,
              sourceId: 'artist-$id',
              createdAt: now,
              updatedAt: now,
              totalCount: status == OfflineDownloadStatus.downloaded ? 1 : 2,
              discoveredCount: status == OfflineDownloadStatus.downloaded
                  ? 1
                  : 0,
              completedCount: status == OfflineDownloadStatus.downloaded
                  ? 1
                  : 0,
            ),
            batch: OfflineDownloadBatch(
              batchId: id,
              serverBaseUrl: _server,
              status: status,
              createdAt: now,
              updatedAt: now,
              totalCount: status == OfflineDownloadStatus.downloaded ? 1 : 2,
              completedCount: status == OfflineDownloadStatus.downloaded
                  ? 1
                  : 0,
            ),
            items: [
              OfflineDownloadJobItem(
                jobId: id,
                position: 0,
                serverTrackId: id,
                status: status,
                materialized: true,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            sources: [
              OfflineDownloadJobSource(
                jobId: id,
                position: 0,
                sourceId: 'album-$id',
                status: status == OfflineDownloadStatus.downloaded
                    ? OfflineDownloadStatus.downloaded
                    : OfflineDownloadStatus.failed,
                createdAt: now,
                updatedAt: now,
                error: 'cached failure',
              ),
            ],
          );
        }
        final manager = OfflineDownloadManager(
          connection: _Connection(),
          storage: storage,
        );
        await manager.load();
        if (unfinishedOnly) {
          await manager.clearUnfinishedDownloads();
          expect((await storage.readLocalPlaylists()).single.id, playlist.id);
          expect(manager.localPlaylists.single.id, playlist.id);
          expect(await File(playlistWithImage.imagePath!).exists(), isTrue);
        } else {
          await manager.resetLocalData();
          expect(await storage.readLocalPlaylists(), isEmpty);
        }
        final expectedIds = unfinishedOnly ? ['downloaded'] : <String>[];
        expect(
          manager.downloadSnapshot.downloads.map(
            (item) => item.track.serverTrackId ?? item.track.id,
          ),
          expectedIds,
        );
        expect(manager.downloadSnapshot.jobs, isEmpty);
        expect(manager.downloadSnapshot.batches, isEmpty);
        expect(manager.librarySnapshot.tracks, hasLength(expectedIds.length));
        for (final entry in files.entries) {
          expect(
            await entry.value.exists(),
            unfinishedOnly && entry.key == OfflineDownloadStatus.downloaded,
          );
        }
        expect(
          (await storage.readDownloads()).map(
            (item) => item.track.serverTrackId ?? item.track.id,
          ),
          expectedIds,
        );
        expect(await storage.readDownloadJobs(), isEmpty);
        expect(await storage.readDownloadBatches(), isEmpty);
        for (final status in OfflineDownloadStatus.values) {
          expect(await storage.readDownloadJobItems(status.name), isEmpty);
          expect(await storage.readDownloadJobSources(status.name), isEmpty);
        }
        expect(
          await storage.readOrCreateClientId(),
          unfinishedOnly ? oldClientId : isNot(oldClientId),
        );
        await manager.dispose();
        await storage.close();
        final connection = _Connection()..setToken('restored-session');
        final restored = OfflineDownloadManager(
          connection: connection,
          storage: OfflineLibraryStorage(baseDirectory: root),
        );
        addTearDown(restored.dispose);
        addTearDown(storage.close);
        await restored.load();
        await restored.resumePausedForCurrentServer();
        expect(
          restored.downloads.map(
            (item) => item.track.serverTrackId ?? item.track.id,
          ),
          expectedIds,
        );
        expect(restored.jobs, isEmpty);
        expect(restored.batches, isEmpty);
      },
    );
  }

  test(
    'clearing a mixed job keeps completed songs and their local library data',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_partial_clear_',
      );
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final manager = OfflineDownloadManager(
        connection: _Connection(),
        storage: storage,
      );
      addTearDown(() async {
        await manager.dispose();
        await storage.close();
        await root.delete(recursive: true);
      });
      final art = await storage.albumArtFile(
        albumId: 'album-1',
        extension: 'png',
      );
      await art.writeAsBytes([4, 5, 6]);
      final metadata = offlineTestOfflineMetadata(
        trackId: 'song',
        albumArtPath: art.path,
      );
      final file = await storage.trackFile(
        serverBaseUrl: _server,
        trackId: 'song',
      );
      await file.writeAsBytes([1, 2, 3]);
      final completed = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: _server,
          batchId: 'mixed',
          track: metadata.track,
          filePath: file.path,
        ).copyWith(offlineMetadata: metadata),
      );
      await storage.upsertDownload(completed);
      final partial = await storage.partialTrackFile(
        serverBaseUrl: _server,
        trackId: 'unfinished',
      );
      await partial.writeAsBytes([1]);
      await storage.upsertDownload(
        await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: _server,
            batchId: 'mixed',
            track: offlineTestTrack(id: 'unfinished', title: 'Unfinished'),
            status: OfflineDownloadStatus.paused,
          ).copyWith(
            partialPath: partial.path,
            bytesDownloaded: 1,
            bytesTotal: 3,
          ),
        ),
      );
      final orphan = await storage.partialTrackFile(
        serverBaseUrl: _server,
        trackId: 'orphan',
      );
      await orphan.writeAsBytes([7]);
      final now = DateTime.now();
      await storage.saveDownloadPlan(
        job: OfflineDownloadJob(
          jobId: 'mixed',
          kind: 'album',
          serverBaseUrl: _server,
          status: OfflineDownloadStatus.paused,
          createdAt: now,
          updatedAt: now,
          totalCount: 2,
          discoveredCount: 2,
          completedCount: 1,
        ),
        batch: OfflineDownloadBatch(
          batchId: 'mixed',
          serverBaseUrl: _server,
          status: OfflineDownloadStatus.paused,
          createdAt: now,
          updatedAt: now,
          totalCount: 2,
          completedCount: 1,
        ),
        items: [
          for (final entry in [
            (id: 'song', status: OfflineDownloadStatus.downloaded),
            (id: 'unfinished', status: OfflineDownloadStatus.paused),
          ])
            OfflineDownloadJobItem(
              jobId: 'mixed',
              position: entry.id == 'song' ? 0 : 1,
              serverTrackId: entry.id,
              status: entry.status,
              materialized: true,
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );
      final localId = completed.localTrackId!;
      await storage.setLocalLike(localId, true);
      final playlist = await storage.createLocalPlaylist('Saved songs');
      await storage.addLocalTrackToPlaylist(playlist.id, localId);
      await manager.load();
      await manager.loadLocalPlaylistTracks(playlist.id);

      await manager.clearUnfinishedDownloads();

      expect(manager.downloads.single.localTrackId, localId);
      expect(manager.downloads.single.status, OfflineDownloadStatus.downloaded);
      expect(manager.librarySnapshot.tracks.single.id, localId);
      expect(manager.localLiked.single.id, localId);
      expect(manager.localPlaylistTracks.single.id, localId);
      expect(manager.localPlaylists.single.id, playlist.id);
      expect(manager.jobs, isEmpty);
      expect(manager.batches, isEmpty);
      expect(await File(manager.downloads.single.filePath!).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await art.readAsBytes(), [4, 5, 6]);
      expect(
        (await storage.readDownloads()).single.offlineMetadata?.track.title,
        metadata.track.title,
      );
      expect(await partial.exists(), isFalse);
      expect(await orphan.exists(), isFalse);
      expect(await storage.readDownloadJobItems('mixed'), isEmpty);

      // Repeating the operation with only completed songs is harmless.
      await manager.clearUnfinishedDownloads();
      expect(manager.librarySnapshot.tracks.single.id, localId);
      expect(await file.exists(), isTrue);
      expect((await storage.readLocalLikedTracks()).single.id, localId);
      expect(
        (await storage.readLocalPlaylistTracks(playlist.id)).single.id,
        localId,
      );
    },
  );

  for (final action in ['full reset', 'cache clear', 'artist deletion']) {
    final resetAll = action != 'artist deletion';
    test(
      'a response after $action cannot restore jobs or failed items',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'phonolite_reset_response_',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: root);
        if (!resetAll) await _saveCompleted(storage, metadata: true);
        final connection = _PendingV2Connection()..setToken('session');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();
        final request = manager.queueArtist(
          Artist(id: 'artist-1', name: 'Artist', albumCount: 1),
          [
            Album(
              id: 'album-1',
              title: 'Album',
              artist: 'Artist',
              artistId: 'artist-1',
              trackCount: 1,
            ),
          ],
        );
        await connection.requested.future;
        if (action == 'cache clear') {
          await manager.clearUnfinishedDownloads();
        } else if (resetAll) {
          await manager.resetLocalData();
        } else {
          await manager.removeDownloads(
            manager.downloads.where((download) => download.isDownloaded),
            scope: const OfflineDeletionScope.artist(
              id: 'artist-1',
              label: 'Artist',
            ),
          );
        }
        final now = DateTime.now();
        connection.response.complete(
          DownloadJobV2(
            jobId: '92fd40d2-5d72-4c00-b228-ed595abcd130',
            clientId: 'old-client',
            clientRequestId: 'old-request',
            scope: DownloadJobScopeV2(kind: 'artist', id: 'artist-1'),
            status: 'metadata_failed',
            createdAt: now,
            updatedAt: now,
            totalCount: 1,
            readyCount: 0,
            completedCount: 0,
            failedCount: 1,
            eventCursor: 0,
            items: [
              DownloadJobItemV2(
                position: 0,
                trackId: 'song',
                status: 'metadata_failed',
                error: 'old failure',
              ),
            ],
          ),
        );
        await request;
        expect(manager.jobs, isEmpty);
        expect(manager.downloads, isEmpty);
        expect(manager.batches, isEmpty);
        expect(await storage.readDownloadJobs(), isEmpty);
      },
    );
  }

  test(
    'old metadata cannot overwrite a fresh download after cache clear',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_reset_metadata_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      await _saveCompleted(storage);
      final connection = _PendingMetadataConnection()..setToken('session');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final repair = manager.repairOfflineMetadataFragments();
      await connection.requested.future;
      await manager.clearUnfinishedDownloads();
      await _saveCompleted(storage, title: 'Fresh download', metadata: true);
      await manager.load();
      connection.response.complete(
        offlineTestOfflineMetadata(
          trackId: 'song',
          trackTitle: 'Old cached title',
        ),
      );
      await repair;
      expect(
        (await storage.readDownloads()).single.track.title,
        'Fresh download',
      );
      expect(manager.downloads.single.track.title, 'Fresh download');
    },
  );

  test(
    'cache clear drains an active download before clearing its cached state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_reset_preparing_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = _PreparingStorage(root);
      await storage.upsertDownload(
        await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: _server,
            track: offlineTestTrack(id: 'song'),
            status: OfflineDownloadStatus.queued,
          ),
        ),
      );
      final manager = OfflineDownloadManager(
        connection: _Connection()..setToken('session'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      await storage.preparing.future;
      final reset = manager.clearUnfinishedDownloads();
      storage.proceed.complete();
      await reset;
      expect(manager.downloads, isEmpty);
      expect(manager.jobs, isEmpty);
      expect(await storage.readDownloads(), isEmpty);
      expect(await storage.readPendingFileDeletes(), isEmpty);
      await manager.load();
      expect(manager.downloads, isEmpty);
    },
  );

  test(
    'cache clear waits for an already-started plan commit and removes it',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_reset_plan_commit_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = _SavingPlanStorage(root);
      final manager = OfflineDownloadManager(
        connection: _Connection(),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final request = manager
          .queueArtist(Artist(id: 'artist', name: 'Artist', albumCount: 1), [
            Album(
              id: 'album',
              title: 'Album',
              artist: 'Artist',
              artistId: 'artist',
              trackCount: 1,
            ),
          ]);
      await storage.saving.future;
      var finished = false;
      final reset = manager.clearUnfinishedDownloads().then(
        (_) => finished = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      storage.proceed.complete();
      await Future.wait([request, reset]);
      expect(manager.jobs, isEmpty);
      expect(manager.batches, isEmpty);
      expect(await storage.readDownloadJobs(), isEmpty);
      expect(await storage.readDownloadBatches(), isEmpty);
    },
  );
}
