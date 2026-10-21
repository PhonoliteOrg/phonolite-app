import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/offline_library_test_helpers.dart';

class _Connection extends ServerConnection {
  _Connection({this.tracksPerAlbum = 1})
    : super(
        baseUrl: 'https://restart.test:3000/api/v1',
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );

  final requestedAlbums = <String>[];
  final requestedBatches = <List<String>>[];
  final int tracksPerAlbum;

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    requestedAlbums.add(albumId);
    return [
      for (var index = 1; index <= tracksPerAlbum; index++)
        offlineTestTrack(
          id: tracksPerAlbum == 1 ? '$albumId-song' : '$albumId-song-$index',
        ),
    ];
  }

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    requestedBatches.add(List.of(trackIds));
    // Verify planning without starting any socket or media worker.
    setToken(null);
    final now = DateTime.now();
    return DownloadBatchManifest(
      schemaVersion: 1,
      batchId: clientBatchId ?? 'restored-batch',
      createdAt: now,
      items: [
        for (final id in trackIds)
          offlineTestDownloadManifest(
            batchId: 'fixture',
            trackId: id,
          ).items.single,
      ],
      unavailable: const [],
    );
  }
}

class _GatedArtistConnection extends _Connection {
  final discoveryStarted = Completer<void>();
  final finishDiscovery = Completer<void>();

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    if (albumId == 'first-album') {
      discoveryStarted.complete();
      await finishDiscovery.future;
      return [];
    }
    return super.fetchTracks(albumId);
  }
}

class _FailingDiscoveryConnection extends _Connection {
  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    requestedAlbums.add(albumId);
    setToken(null);
    throw const SocketException('Connection interrupted during album lookup');
  }
}

class _V2ArtistConnection extends _Connection {
  final requestStarted = Completer<void>();
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
    requestStarted.complete();
    final job = await response.future;
    setToken(null);
    return DownloadJobV2(
      jobId: job.jobId,
      clientId: clientId,
      clientRequestId: clientRequestId,
      scope: job.scope,
      status: job.status,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      totalCount: job.totalCount,
      readyCount: job.readyCount,
      completedCount: job.completedCount,
      failedCount: job.failedCount,
      eventCursor: job.eventCursor,
      items: job.items,
    );
  }
}

class _PreparingStorage extends OfflineLibraryStorage {
  _PreparingStorage(Directory root) : super(baseDirectory: root);

  bool blockPreparation = false;
  final preparing = Completer<String>();
  final proceed = Completer<void>();

  @override
  Future<File> partialTrackFile({
    required String serverBaseUrl,
    required String trackId,
  }) async {
    if (blockPreparation) {
      if (!preparing.isCompleted) preparing.complete(trackId);
      await proceed.future;
    }
    return super.partialTrackFile(
      serverBaseUrl: serverBaseUrl,
      trackId: trackId,
    );
  }
}

final _artist = Artist(id: 'artist', name: 'Artist', albumCount: 3);
final _albums = [
  for (var index = 1; index <= 3; index++)
    Album(
      id: 'album-$index',
      title: 'Album $index',
      artist: _artist.name,
      artistId: _artist.id,
      trackCount: 1,
    ),
];

DownloadJobV2 _artistResponse({int tracksPerAlbum = 1, int manifestCount = 1}) {
  final now = DateTime.now();
  return DownloadJobV2(
    jobId: '92fd40d2-5d72-4c00-b228-ed595abcd130',
    clientId: 'fixture-client',
    clientRequestId: 'fixture-request',
    scope: DownloadJobScopeV2(kind: 'artist', id: _artist.id),
    status: 'ready_to_download',
    createdAt: now,
    updatedAt: now,
    totalCount: 3 * tracksPerAlbum,
    readyCount: manifestCount,
    completedCount: 0,
    failedCount: 0,
    eventCursor: 0,
    items: [
      for (var index = 0; index < manifestCount; index++)
        DownloadJobItemV2(
          position: index,
          trackId: tracksPerAlbum == 1
              ? 'album-1-song'
              : 'album-1-song-${index + 1}',
          status: 'ready_to_download',
          offlineMetadata: offlineTestDownloadManifest(
            batchId: 'fixture',
            trackId: tracksPerAlbum == 1
                ? 'album-1-song'
                : 'album-1-song-${index + 1}',
          ).items.single.offlineMetadata,
        ),
    ],
  );
}

Future<void> _completeStagedDownloads(OfflineLibraryStorage storage) async {
  for (final download in await storage.readDownloads()) {
    if (download.status == OfflineDownloadStatus.downloaded) continue;
    final file = await storage.trackFile(
      serverBaseUrl: download.serverBaseUrl,
      trackId: download.track.serverTrackId ?? download.track.id,
    );
    final length = download.bytesTotal ?? 4;
    await file.writeAsBytes(List.filled(length, 1));
    await storage.upsertDownload(
      download.copyWith(
        status: OfflineDownloadStatus.downloaded,
        filePath: file.path,
        bytesDownloaded: length,
      ),
    );
    // Leave the job item untouched to exercise recovery after a crash between
    // saving the finished file and updating its collection's progress.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final status in [
    OfflineDownloadStatus.preparing,
    OfflineDownloadStatus.downloading,
    OfflineDownloadStatus.validating,
  ]) {
    for (final alreadyConnected in [false, true]) {
      test(
        'startup resumes $status with partial bytes (connected: $alreadyConnected)',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'phonolite_partial_restart_',
          );
          addTearDown(() => root.delete(recursive: true));
          final storage = _PreparingStorage(root);
          final connection = _Connection();
          final partial = await storage.partialTrackFile(
            serverBaseUrl: connection.baseUrl,
            trackId: 'in-progress',
          );
          await partial.writeAsBytes([1, 2, 3]);
          final completed = await storage.trackFile(
            serverBaseUrl: connection.baseUrl,
            trackId: 'done',
          );
          await completed.writeAsBytes([4, 5, 6]);
          await storage.upsertDownloads(
            await storage.prepareDownloads([
              offlineTestDownload(
                serverBaseUrl: connection.baseUrl,
                track: offlineTestTrack(id: 'in-progress'),
                status: status,
              ).copyWith(
                partialPath: partial.path,
                bytesDownloaded: 1,
                bytesTotal: 10,
                etag: 'unchanged-file',
              ),
              offlineTestDownload(
                serverBaseUrl: connection.baseUrl,
                track: offlineTestTrack(id: 'done'),
                filePath: completed.path,
              ),
              offlineTestDownload(
                serverBaseUrl: connection.baseUrl,
                track: offlineTestTrack(id: 'canceled'),
                status: OfflineDownloadStatus.canceled,
              ),
            ]),
          );
          storage.blockPreparation = true;
          if (alreadyConnected) connection.setToken('saved-session');
          final manager = OfflineDownloadManager(
            connection: connection,
            storage: storage,
          );
          try {
            await manager.load();
            if (!alreadyConnected) {
              expect(
                manager.findForCurrentServer('in-progress')!.status,
                OfflineDownloadStatus.queued,
              );
              expect(storage.preparing.isCompleted, isFalse);
              connection.setToken('restored-session');
              await manager.resumePausedForCurrentServer();
            }
            expect(
              await storage.preparing.future.timeout(
                const Duration(seconds: 1),
              ),
              'in-progress',
            );
            final resumed = manager.findForCurrentServer('in-progress')!;
            expect(resumed.status, OfflineDownloadStatus.preparing);
            expect(resumed.partialPath, partial.path);
            expect(resumed.etag, 'unchanged-file');
            // The worker reads the actual partial length, including bytes written
            // just before a crash that had not yet reached the database.
            expect(await partial.readAsBytes(), [1, 2, 3]);
            expect(
              manager.findForCurrentServer('done')!.status,
              OfflineDownloadStatus.downloaded,
            );
            expect(await completed.readAsBytes(), [4, 5, 6]);
            expect(
              manager.findForCurrentServer('canceled')!.status,
              OfflineDownloadStatus.canceled,
            );
          } finally {
            // Stop at file preparation: these tests never open a socket or run
            // the media transfer worker.
            final closing = manager.dispose();
            storage.proceed.complete();
            await closing;
            await storage.close();
          }
        },
      );
    }
  }

  test(
    'artist intent is saved before waiting for a v2 server response',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_intent_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _V2ArtistConnection()..setToken('session');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final queued = manager.queueArtist(_artist, _albums);
      await connection.requestStarted.future;
      // Always release the fixture, including when an assertion fails.
      addTearDown(() async {
        connection.response.complete(_artistResponse());
        await queued;
      });
      final jobs = await storage.readDownloadJobs();
      expect(jobs, hasLength(1));
      expect(jobs.single.sourceId, _artist.id);
      expect(
        (await storage.readDownloadJobSources(
          jobs.single.jobId,
        )).map((source) => source.sourceId),
        _albums.map((album) => album.id),
      );
    },
  );

  test('artist discovery retries after several interrupted restarts', () async {
    final root = await Directory.systemTemp.createTemp(
      'phonolite_artist_retries_',
    );
    addTearDown(() => root.delete(recursive: true));
    String? jobId;
    for (var attempt = 0; attempt < 3; attempt++) {
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = attempt < 2
          ? _FailingDiscoveryConnection()
          : _Connection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      try {
        await manager.load();
        if (attempt == 0) {
          await manager.queueArtist(_artist, [_albums.first]);
          jobId = manager.jobs.single.jobId;
        }
        connection.setToken('restored-session');
        await manager.resumePausedForCurrentServer();
        if (attempt < 2) {
          await offlineTestWaitFor(() => manager.jobs.single.failedCount == 1);
          expect(await storage.readDownloadJobs(), hasLength(1));
        } else {
          await offlineTestWaitFor(() => manager.downloads.isNotEmpty);
          expect(manager.downloads.single.track.id, 'album-1-song');
          expect(manager.jobs.single.jobId, jobId);
        }
        expect(connection.requestedAlbums, ['album-1']);
      } finally {
        await manager.dispose();
        await storage.close();
      }
    }
  });

  test(
    're-requesting a v2 artist keeps completed files and finishes its plan',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_existing_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _V2ArtistConnection()..setToken('session');
      connection.response.complete(_artistResponse());
      final file = await storage.trackFile(
        serverBaseUrl: connection.baseUrl,
        trackId: 'album-1-song',
      );
      await file.writeAsBytes([1]);
      await storage.upsertDownload(
        await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: connection.baseUrl,
            track: offlineTestTrack(id: 'album-1-song'),
            filePath: file.path,
          ),
        ),
      );
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      await manager.load();
      expect(await manager.queueArtist(_artist, _albums), 3);
      final jobId = manager.jobs.single.jobId;
      expect(
        (await storage.readDownloadJobItems(jobId)).single.status,
        OfflineDownloadStatus.downloaded,
      );
      expect(manager.downloads.single.filePath, file.path);
      connection.setToken('session');
      await manager.resumePausedForCurrentServer();
      await offlineTestWaitFor(() => manager.downloads.length == 3);
      expect(connection.requestedBatches.single, [
        'album-2-song',
        'album-3-song',
      ]);
      await manager.dispose();
      await _completeStagedDownloads(storage);
      await storage.close();

      final restored = OfflineDownloadManager(
        connection: _Connection(),
        storage: OfflineLibraryStorage(baseDirectory: root),
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.jobs, isEmpty);
      expect(
        restored.downloads.every((download) => download.isDownloaded),
        isTrue,
      );
      expect(await file.readAsBytes(), [1]);
    },
  );

  test('v2 artist finishes all 75 tracks across four interrupted windows', () async {
    final root = await Directory.systemTemp.createTemp(
      'phonolite_artist_windows_',
    );
    addTearDown(() => root.delete(recursive: true));
    final initialStorage = OfflineLibraryStorage(baseDirectory: root);
    final initialConnection = _V2ArtistConnection()..setToken('session');
    initialConnection.response.complete(
      _artistResponse(tracksPerAlbum: 25, manifestCount: 25),
    );
    final initial = OfflineDownloadManager(
      connection: initialConnection,
      storage: initialStorage,
    );
    await initial.load();
    expect(
      await initial.queueArtist(_artist, [
        for (final album in _albums) album.copyWith(trackCount: 25),
      ]),
      75,
    );
    expect(initial.downloads, hasLength(20));
    expect(
      await initialStorage.readDownloadJobSources(initial.jobs.single.jobId),
      hasLength(3),
    );
    await initial.dispose();
    await _completeStagedDownloads(initialStorage);
    await initialStorage.close();

    for (var restart = 1; restart <= 4; restart++) {
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _Connection(tracksPerAlbum: 25)
        ..setToken('restored-session');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      try {
        await manager.load();
        if (restart == 4) {
          expect(
            manager.jobs,
            isEmpty,
            reason:
                '${manager.jobs.map((job) => '${job.status}/${job.completedCount}/${job.discoveredCount}/${job.failedCount}').toList()}; ${manager.downloads.length} downloads; ${connection.requestedAlbums}',
          );
          expect(manager.downloads, hasLength(75));
          expect(
            manager.downloads.every((download) => download.isDownloaded),
            isTrue,
          );
          expect(await storage.readDownloadJobs(), isEmpty);
        } else {
          expect(manager.jobs, hasLength(1));
          await manager.resumePausedForCurrentServer();
          final expectedCount = restart == 3 ? 75 : (restart + 1) * 20;
          try {
            await offlineTestWaitFor(
              () => manager.downloads.length == expectedCount,
            );
          } catch (error) {
            fail(
              'Restart $restart: expected $expectedCount, got ${manager.downloads.length}; '
              'jobs ${manager.jobs.map((job) => '${job.status}/${job.completedCount}/${job.discoveredCount}/${job.failedCount}').toList()}; '
              'lookups ${connection.requestedAlbums}; batches ${connection.requestedBatches}; $error',
            );
          }
          expect(manager.jobs.single.sourceId, _artist.id);
          expect(manager.jobs.single.totalCount, 75);
        }
      } finally {
        await manager.dispose();
      }
      await _completeStagedDownloads(storage);
      await storage.close();
    }
  });

  test(
    'missing staged rows are rebuilt from the saved artist request',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_missing_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final now = DateTime.now();
      await storage.saveDownloadPlan(
        job: OfflineDownloadJob(
          jobId: 'interrupted-staging',
          kind: 'artist',
          serverBaseUrl: _Connection().baseUrl,
          status: OfflineDownloadStatus.downloading,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
        ),
        batch: OfflineDownloadBatch(
          batchId: 'interrupted-staging',
          totalCount: 1,
          serverBaseUrl: _Connection().baseUrl,
          status: OfflineDownloadStatus.downloading,
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          OfflineDownloadJobItem(
            jobId: 'interrupted-staging',
            position: 0,
            serverTrackId: 'song',
            status: OfflineDownloadStatus.downloading,
            materialized: true,
            createdAt: now,
            updatedAt: now,
            track: offlineTestTrack(id: 'song'),
          ),
        ],
      );
      final connection = _Connection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      expect(manager.jobs, hasLength(1));
      connection.setToken('session');
      await manager.resumePausedForCurrentServer();
      await offlineTestWaitFor(() => manager.downloads.isNotEmpty);
      expect(manager.downloads.single.track.id, 'song');
    },
  );

  test(
    'restored queued artist resumes discovery even without paused track rows',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_restart_artist_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _Connection();
      final now = DateTime.now();
      await storage.upsertDownloadJob(
        OfflineDownloadJob(
          jobId: 'restored-artist',
          kind: 'artist',
          serverBaseUrl: connection.baseUrl,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
          sourceId: 'artist',
        ),
      );
      await storage.upsertDownloadJobSources([
        OfflineDownloadJobSource(
          jobId: 'restored-artist',
          position: 0,
          sourceId: 'album',
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      expect(manager.downloads, isEmpty);
      expect(manager.jobs.single.status, OfflineDownloadStatus.queued);
      connection.setToken('test-session');
      await manager.resumePausedForCurrentServer();
      await offlineTestWaitFor(() => manager.downloads.isNotEmpty);
      expect(connection.requestedAlbums, ['album']);
      expect(manager.downloads.single.track.id, 'album-song');
      expect(
        (await storage.readDownloadJobSources('restored-artist')).single.status,
        OfflineDownloadStatus.downloaded,
      );
    },
  );

  test(
    'an album keeps all unstaged tracks across restart and waits for restored authentication',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_restart_album_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final first = OfflineDownloadManager(
        connection: _Connection(),
        storage: storage,
      );
      await first.load();
      final tracks = [
        for (var index = 1; index <= 25; index++)
          offlineTestTrack(id: 'song-$index'),
      ];
      expect(
        await first.queueTracks(
          tracks,
          kind: 'album',
          sourceId: 'album',
          label: 'Album',
        ),
        25,
      );
      final jobId = first.jobs.single.jobId;
      expect((await storage.readDownloadJobItems(jobId)), hasLength(25));
      expect(first.downloads, isEmpty);
      await first.dispose();
      await storage.close();

      final restoredStorage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _Connection();
      final restored = OfflineDownloadManager(
        connection: connection,
        storage: restoredStorage,
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.jobs.single.jobId, jobId);
      expect(restored.jobs.single.totalCount, 25);
      expect(restored.downloads, isEmpty);
      connection.setToken('restored-session');
      await restored.resumePausedForCurrentServer();
      await offlineTestWaitFor(() => restored.downloads.length == 20);
      expect(
        connection.requestedBatches.single,
        tracks.take(20).map((track) => track.id).toList(),
      );
      await offlineTestWaitFor(
        () async =>
            (await restoredStorage.readDownloadJobItems(
              jobId,
            )).where((item) => !item.materialized).length ==
            5,
      );
      final items = await restoredStorage.readDownloadJobItems(jobId);
      expect(items, hasLength(25));
      expect(items.where((item) => !item.materialized), hasLength(5));
      expect(restored.jobs.single.totalCount, 25);
    },
  );

  test(
    'a failed plan commit rolls back the full request and never starts staging',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_restart_commit_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      await storage.readDownloadJobs();
      final db = sqlite3.open(
        offlineTestJoin(
          offlineTestJoin(root.path, 'offline'),
          'phonolite_offline.sqlite',
        ),
      );
      db.execute(
        "CREATE TRIGGER fail_plan_item BEFORE INSERT ON download_job_items BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END",
      );
      db.dispose();
      final manager = OfflineDownloadManager(
        connection: _Connection(),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      await expectLater(
        manager.queueBatch(
          offlineTestDownloadManifest(
            batchId: 'failed-plan',
            trackId: 'song',
            itemCount: 25,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(manager.jobs, isEmpty);
      expect(manager.downloads, isEmpty);
      expect(await storage.readDownloadJobs(), isEmpty);
      expect(await storage.readDownloadBatches(), isEmpty);
      expect(await storage.readDownloadJobItems('failed-plan'), isEmpty);
      expect(await storage.readDownloads(), isEmpty);
    },
  );

  test(
    'artist discovery cannot persist completion without its discovered tracks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_restart_discovery_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final now = DateTime.now();
      final job = OfflineDownloadJob(
        jobId: 'discovery',
        kind: 'artist',
        serverBaseUrl: _Connection().baseUrl,
        status: OfflineDownloadStatus.queued,
        createdAt: now,
        updatedAt: now,
      );
      final source = OfflineDownloadJobSource(
        jobId: job.jobId,
        position: 0,
        sourceId: 'album',
        status: OfflineDownloadStatus.queued,
        createdAt: now,
        updatedAt: now,
      );
      await storage.saveDownloadPlan(
        job: job,
        sources: [source],
        batch: OfflineDownloadBatch(
          batchId: job.jobId,
          totalCount: 1,
          serverBaseUrl: job.serverBaseUrl,
          status: job.status,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final db = sqlite3.open(
        offlineTestJoin(
          offlineTestJoin(root.path, 'offline'),
          'phonolite_offline.sqlite',
        ),
      );
      db.execute(
        "CREATE TRIGGER fail_discovery BEFORE UPDATE ON download_job_sources BEGIN SELECT RAISE(ABORT, 'simulated progress failure'); END",
      );
      db.dispose();
      await expectLater(
        storage.saveDownloadJobDiscovery(
          items: [
            OfflineDownloadJobItem(
              jobId: job.jobId,
              position: 0,
              serverTrackId: 'song',
              status: OfflineDownloadStatus.queued,
              materialized: false,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          sources: [source.copyWith(status: OfflineDownloadStatus.downloaded)],
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(await storage.readDownloadJobItems(job.jobId), isEmpty);
      expect(
        (await storage.readDownloadJobSources(job.jobId)).single.status,
        OfflineDownloadStatus.queued,
      );
      expect(await storage.readDownloadJobs(), hasLength(1));
    },
  );

  test(
    'reconnect requests another staging pass when discovery is already running',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_restart_wakeup_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final connection = _GatedArtistConnection()..setToken('test-session');
      final now = DateTime.now();
      for (final first in [true, false]) {
        final id = first ? 'first' : 'second';
        final status = first
            ? OfflineDownloadStatus.queued
            : OfflineDownloadStatus.paused;
        await storage.saveDownloadPlan(
          job: OfflineDownloadJob(
            jobId: id,
            kind: 'artist',
            serverBaseUrl: connection.baseUrl,
            status: status,
            createdAt: now,
            updatedAt: now,
          ),
          sources: [
            OfflineDownloadJobSource(
              jobId: id,
              position: 0,
              sourceId: '$id-album',
              status: OfflineDownloadStatus.queued,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          batch: OfflineDownloadBatch(
            batchId: id,
            totalCount: 1,
            serverBaseUrl: connection.baseUrl,
            status: status,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      await connection.discoveryStarted.future;
      await manager.resumePausedForCurrentServer();
      connection.finishDiscovery.complete();
      await offlineTestWaitFor(() => manager.downloads.isNotEmpty);
      expect(connection.requestedAlbums, ['second-album']);
      expect(manager.downloads.single.track.id, 'second-album-song');
    },
  );
}
