import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/server_connection.dart';

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

  test(
    'full reset clears every download status and plan across restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_reset_states_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final now = DateTime.now();
      final oldClientId = await storage.readOrCreateClientId();
      final files = <File>[];
      for (final status in OfflineDownloadStatus.values) {
        final id = status.name;
        final file = await storage.partialTrackFile(
          serverBaseUrl: _server,
          trackId: id,
        );
        await file.writeAsBytes([1, 2, 3]);
        files.add(file);
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
            totalCount: 2,
          ),
          batch: OfflineDownloadBatch(
            batchId: id,
            serverBaseUrl: _server,
            status: status,
            createdAt: now,
            updatedAt: now,
            totalCount: 2,
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
              status: OfflineDownloadStatus.failed,
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
      await manager.resetLocalData();
      expect(manager.downloadSnapshot.downloads, isEmpty);
      expect(manager.downloadSnapshot.jobs, isEmpty);
      expect(manager.downloadSnapshot.batches, isEmpty);
      expect(manager.librarySnapshot.tracks, isEmpty);
      for (final file in files) {
        expect(await file.exists(), isFalse);
      }
      expect(await storage.readDownloads(), isEmpty);
      expect(await storage.readDownloadJobs(), isEmpty);
      expect(await storage.readDownloadBatches(), isEmpty);
      for (final status in OfflineDownloadStatus.values) {
        expect(await storage.readDownloadJobItems(status.name), isEmpty);
        expect(await storage.readDownloadJobSources(status.name), isEmpty);
      }
      expect(await storage.readOrCreateClientId(), isNot(oldClientId));
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
      expect(restored.downloads, isEmpty);
      expect(restored.jobs, isEmpty);
      expect(restored.batches, isEmpty);
    },
  );

  for (final resetAll in [true, false]) {
    test(
      'a response after ${resetAll ? 'full reset' : 'artist deletion'} cannot restore jobs or failed items',
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
        if (resetAll) {
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

  test('old metadata cannot overwrite a fresh download after reset', () async {
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
    await manager.resetLocalData();
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
  });

  test(
    'reset drains an active download before clearing its cached state',
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
      final reset = manager.resetLocalData();
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
    'reset waits for an already-started plan commit and removes it',
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
      final reset = manager.resetLocalData().then((_) => finished = true);
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
