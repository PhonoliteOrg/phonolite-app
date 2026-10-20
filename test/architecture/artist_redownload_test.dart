import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _server = 'https://redownload.test:3000/api/v1';
const _oldJobId = '92fd40d2-5d72-4c00-b228-ed595abcd130';
final _artist = Artist(id: 'artist-1', name: 'Artist', albumCount: 1);
final _album = Album(
  id: 'album-1',
  title: 'Album',
  artist: 'Artist',
  artistId: 'artist-1',
  trackCount: 2,
);

OfflineTrackMetadata _metadata(String id, {bool old = false}) =>
    offlineTestOfflineMetadata(
      trackId: id,
      trackTitle: '${old ? 'Old' : 'Current'} $id',
      artistName: 'Artist',
    );

DownloadJobV2 _job(
  String clientId,
  String requestId, {
  bool old = false,
  int sequence = 1,
  List<String> trackIds = const ['song', 'done'],
}) {
  final now = DateTime.now();
  return DownloadJobV2(
    jobId: old
        ? _oldJobId
        : '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
    clientId: clientId,
    clientRequestId: requestId,
    scope: DownloadJobScopeV2(kind: 'artist', id: _artist.id),
    status: 'ready_to_download',
    createdAt: now,
    updatedAt: now,
    totalCount: trackIds.length,
    readyCount: old ? 1 : trackIds.length,
    completedCount: 0,
    failedCount: old ? 1 : 0,
    eventCursor: 0,
    items: [
      for (final (position, id) in trackIds.indexed)
        DownloadJobItemV2(
          position: position,
          trackId: id,
          status: old && id == 'song' ? 'metadata_failed' : 'ready_to_download',
          offlineMetadata: old && id == 'song' ? null : _metadata(id, old: old),
          error: old && id == 'song' ? 'Old cached failure' : null,
          byteLength: 3,
        ),
    ],
  );
}

class _Connection extends ServerConnection {
  _Connection()
    : super(
        baseUrl: _server,
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );

  final jobsByClient = <String, DownloadJobV2>{};
  final requests = <({String clientId, String requestId})>[];
  int freshManifests = 0;

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
    requests.add((clientId: clientId, requestId: clientRequestId));
    // Match the server's scope cache: a new request ID can still return an
    // earlier job belonging to this same device and artist.
    final job = jobsByClient.putIfAbsent(
      clientId,
      () => _job(clientId, clientRequestId, sequence: jobsByClient.length + 1),
    );
    // Planning tests never start media workers or make network connections.
    setToken(null);
    return job;
  }

  @override
  Future<List<Track>> fetchTracks(String albumId) async => [
    for (final id in ['song', 'done']) _metadata(id).track,
  ];

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    freshManifests++;
    setToken(null);
    return DownloadBatchManifest(
      schemaVersion: 1,
      batchId: clientBatchId!,
      createdAt: DateTime.now(),
      unavailable: const [],
      items: [
        for (final id in trackIds)
          DownloadBatchItem(
            trackId: id,
            downloadUrl: '/api/v1/download/tracks/$id',
            offlineMetadata: _metadata(id),
            byteLength: 3,
            contentType: 'audio/mpeg',
            etag: 'new-$id',
            sha256: '',
          ),
      ],
    );
  }
}

class _PendingConnection extends _Connection {
  final pending =
      <
        ({String clientId, String requestId, Completer<DownloadJobV2> response})
      >[];

  @override
  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) async {
    final response = Completer<DownloadJobV2>();
    pending.add((
      clientId: clientId,
      requestId: clientRequestId,
      response: response,
    ));
    final job = await response.future;
    setToken(null);
    return job;
  }
}

class _OverlappingConnection extends _Connection {
  @override
  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) async {
    setToken(null);
    return _job(
      clientId,
      clientRequestId,
      trackIds: ['song', 'done', 'missing'],
    );
  }
}

class _PreparingStorage extends OfflineLibraryStorage {
  _PreparingStorage(Directory root) : super(baseDirectory: root);

  bool blockPreparation = false;
  final preparing = Completer<void>();
  final proceed = Completer<void>();
  final deletionPersisted = Completer<void>();

  @override
  Future<File> partialTrackFile({
    required String serverBaseUrl,
    required String trackId,
  }) async {
    if (blockPreparation) {
      if (!preparing.isCompleted) preparing.complete();
      await proceed.future;
    }
    return super.partialTrackFile(
      serverBaseUrl: serverBaseUrl,
      trackId: trackId,
    );
  }

  @override
  Future<OfflineDeletionResult> removeDownloadsScoped(
    OfflineDeletionRequest request,
  ) async {
    final result = await super.removeDownloadsScoped(request);
    deletionPersisted.complete();
    return result;
  }
}

Future<File> _seedOldState(OfflineLibraryStorage storage) async {
  final partial = await storage.partialTrackFile(
    serverBaseUrl: _server,
    trackId: 'song',
  );
  await partial.writeAsBytes([9, 9, 9]);
  final completed = await storage.trackFile(
    serverBaseUrl: _server,
    trackId: 'done',
  );
  await completed.writeAsBytes([8, 8, 8]);
  await storage.upsertDownloads(
    await storage.prepareDownloads([
      offlineTestDownload(
        serverBaseUrl: _server,
        batchId: _oldJobId,
        track: _metadata('song', old: true).track,
        status: OfflineDownloadStatus.failed,
      ).copyWith(
        partialPath: partial.path,
        bytesDownloaded: 3,
        retryCount: 7,
        error: 'Old cached failure',
      ),
      offlineTestDownload(
        serverBaseUrl: _server,
        batchId: _oldJobId,
        track: _metadata('done', old: true).track,
        filePath: completed.path,
      ),
    ]),
  );
  final now = DateTime.now();
  await storage.saveDownloadPlan(
    job: OfflineDownloadJob(
      jobId: _oldJobId,
      kind: 'artist',
      serverBaseUrl: _server,
      sourceId: _artist.id,
      label: _artist.name,
      status: OfflineDownloadStatus.failed,
      createdAt: now,
      updatedAt: now,
      totalCount: 2,
      failedCount: 1,
    ),
    batch: OfflineDownloadBatch(
      batchId: _oldJobId,
      serverBaseUrl: _server,
      status: OfflineDownloadStatus.failed,
      createdAt: now,
      updatedAt: now,
      totalCount: 2,
    ),
    items: [
      for (final (position, id) in ['song', 'done'].indexed)
        OfflineDownloadJobItem(
          jobId: _oldJobId,
          position: position,
          serverTrackId: id,
          materialized: true,
          status: id == 'song'
              ? OfflineDownloadStatus.failed
              : OfflineDownloadStatus.downloaded,
          createdAt: now,
          updatedAt: now,
          track: _metadata(id, old: true).track,
        ),
    ],
    sources: [
      OfflineDownloadJobSource(
        jobId: _oldJobId,
        position: 0,
        sourceId: _album.id,
        status: OfflineDownloadStatus.failed,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
  return partial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'artist queue preserves album downloads and adds only missing tracks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_overlap_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final partial = await storage.partialTrackFile(
        serverBaseUrl: _server,
        trackId: 'song',
      );
      await partial.writeAsBytes([1, 2]);
      final completed = await storage.trackFile(
        serverBaseUrl: _server,
        trackId: 'done',
      );
      await completed.writeAsBytes([3, 4, 5]);
      await storage.upsertDownloads(
        await storage.prepareDownloads([
          offlineTestDownload(
            serverBaseUrl: _server,
            track: _metadata('song').track,
            batchId: 'album-job',
            status: OfflineDownloadStatus.queued,
          ).copyWith(partialPath: partial.path, bytesDownloaded: 2),
          offlineTestDownload(
            serverBaseUrl: _server,
            track: _metadata('done').track,
            filePath: completed.path,
          ),
        ]),
      );
      final now = DateTime.now();
      await storage.saveDownloadPlan(
        job: OfflineDownloadJob(
          jobId: 'album-job',
          kind: 'album',
          serverBaseUrl: _server,
          sourceId: _album.id,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
        ),
        batch: OfflineDownloadBatch(
          batchId: 'album-job',
          serverBaseUrl: _server,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
        ),
        items: [
          OfflineDownloadJobItem(
            jobId: 'album-job',
            position: 0,
            serverTrackId: 'song',
            status: OfflineDownloadStatus.queued,
            materialized: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final connection = _OverlappingConnection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      try {
        await manager.load();
        connection.setToken('session');
        await manager.queueArtist(_artist, [_album]);
        expect(manager.downloads.map((download) => download.track.id).toSet(), {
          'song',
          'done',
          'missing',
        });
        expect(manager.downloads, hasLength(3));
        final queued = manager.downloads.singleWhere(
          (download) => download.track.id == 'song',
        );
        expect(queued.batchId, 'album-job');
        expect(queued.bytesDownloaded, 2);
        expect(queued.partialPath, partial.path);
        final done = manager.downloads.singleWhere(
          (download) => download.track.id == 'done',
        );
        expect(done.status, OfflineDownloadStatus.downloaded);
        expect(done.filePath, completed.path);
        expect(await completed.readAsBytes(), [3, 4, 5]);
        final missing = manager.downloads.singleWhere(
          (download) => download.track.id == 'missing',
        );
        expect(missing.status, OfflineDownloadStatus.queued);
        expect(missing.batchId, isNot('album-job'));
        expect(
          manager.jobs.map((job) => job.kind),
          containsAll(['album', 'artist']),
        );
        expect(await manager.queueArtist(_artist, [_album]), 0);
      } finally {
        await manager.dispose();
        await storage.close();
      }
    },
  );

  for (final resetAll in [false, true]) {
    test(
      'an old artist response cannot attach to a new request after ${resetAll ? 'reset' : 'deletion'}',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'phonolite_artist_pending_redownload_',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: root);
        await _seedOldState(storage);
        final connection = _PendingConnection();
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        try {
          await manager.load();
          connection.setToken('session');
          final oldRequest = manager.queueArtist(_artist, [_album]);
          await offlineTestWaitFor(() => connection.pending.length == 1);
          final oldPlanId = manager.jobs.single.jobId;
          connection.setToken(null);
          if (resetAll) {
            await manager.resetLocalData();
          } else {
            await manager.removeDownloads(
              manager.downloads,
              scope: OfflineDeletionScope.artist(
                id: _artist.id,
                label: _artist.name,
              ),
            );
          }
          connection.setToken('session');
          final newRequest = manager.queueArtist(_artist, [_album]);
          await offlineTestWaitFor(() => connection.pending.length == 2);
          expect(manager.jobs.single.jobId, isNot(oldPlanId));
          final old = connection.pending.first;
          old.response.complete(_job(old.clientId, old.requestId, old: true));
          expect(await oldRequest, 0);
          expect(manager.jobs.single.failedCount, 0);
          expect(manager.downloads, isEmpty);
          final current = connection.pending.last;
          current.response.complete(
            _job(current.clientId, current.requestId, sequence: 2),
          );
          expect(await newRequest, 2);
          expect(manager.jobs.single.failedCount, 0);
          expect(manager.downloads, hasLength(2));
          expect(
            manager.downloads.every(
              (item) => item.track.title.startsWith('Current '),
            ),
            isTrue,
          );
        } finally {
          for (final pending in connection.pending) {
            if (!pending.response.isCompleted) {
              pending.response.complete(
                _job(pending.clientId, pending.requestId),
              );
            }
          }
          await manager.dispose();
          await storage.close();
        }
      },
    );
  }

  test(
    'deleting an active artist drains its old worker before a fresh request',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_artist_active_redownload_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = _PreparingStorage(root);
      final partial = await _seedOldState(storage);
      await storage.upsertDownloads([
        for (final download in await storage.readDownloads())
          download.status == OfflineDownloadStatus.failed
              ? download.copyWith(status: OfflineDownloadStatus.queued)
              : download,
      ]);
      storage.blockPreparation = true;
      final connection = _Connection()..setToken('session');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      try {
        await manager.load();
        await storage.preparing.future.timeout(const Duration(seconds: 5));
        connection.setToken(null);
        final removal = manager.removeDownloads(
          manager.downloads,
          scope: OfflineDeletionScope.artist(
            id: _artist.id,
            label: _artist.name,
          ),
        );
        await storage.deletionPersisted.future;
        try {
          final finished = await Future.any([
            removal.then((_) => true),
            Future<bool>.delayed(
              const Duration(milliseconds: 150),
              () => false,
            ),
          ]);
          expect(
            finished,
            isFalse,
            reason: 'Deletion must finish stopping the old worker first',
          );
        } finally {
          storage.proceed.complete();
        }
        await removal;
        expect(await partial.exists(), isFalse);
        expect(manager.downloads, isEmpty);
        expect(manager.jobs, isEmpty);
        expect(await storage.readPendingFileDeletes(), isEmpty);
        connection.setToken('session');
        expect(await manager.queueArtist(_artist, [_album]), 2);
        for (final download in manager.downloads) {
          expect(download.status, OfflineDownloadStatus.queued);
          expect(download.retryCount, 0);
          expect(download.bytesDownloaded, 0);
          expect(download.partialPath, isNull);
          expect(download.error, isNull);
        }
      } finally {
        if (!storage.proceed.isCompleted) storage.proceed.complete();
        await manager.dispose();
        await storage.close();
      }
    },
  );

  for (final resetAll in [false, true]) {
    for (final restart in [false, true]) {
      test(
        'artist starts fresh after ${resetAll ? 'reset' : 'offline deletion'} (restart: $restart)',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'phonolite_artist_redownload_',
          );
          addTearDown(() => root.delete(recursive: true));
          var storage = OfflineLibraryStorage(baseDirectory: root);
          final oldClientId = await storage.readOrCreateClientId();
          final partial = await _seedOldState(storage);
          final connection = _Connection();
          connection.jobsByClient[oldClientId] = _job(
            oldClientId,
            'old-request',
            old: true,
          );
          var manager = OfflineDownloadManager(
            connection: connection,
            storage: storage,
          );
          try {
            await manager.load();
            for (var attempt = 0; attempt < 3; attempt++) {
              if (resetAll) {
                await manager.resetLocalData();
              } else {
                await manager.removeDownloads(
                  attempt == 0
                      ? manager.downloads.where((item) => item.isDownloaded)
                      : manager.downloads,
                  scope: OfflineDeletionScope.artist(
                    id: _artist.id,
                    label: _artist.name,
                  ),
                );
              }
              if (restart) {
                await manager.dispose();
                await storage.close();
                storage = OfflineLibraryStorage(baseDirectory: root);
                manager = OfflineDownloadManager(
                  connection: connection,
                  storage: storage,
                );
                await manager.load();
              }
              expect(await partial.exists(), isFalse);
              connection.setToken('session');
              expect(await manager.queueArtist(_artist, [_album]), 2);
              expect(manager.jobs.single.failedCount, 0);
              expect(manager.jobs.single.jobId, isNot(_oldJobId));
              if (manager.downloads.isEmpty) {
                connection.setToken('session');
                await manager.resumePausedForCurrentServer();
              }
              await offlineTestWaitFor(() => manager.downloads.length == 2);
              for (final download in manager.downloads) {
                expect(download.status, OfflineDownloadStatus.queued);
                expect(download.track.title, startsWith('Current '));
                expect(download.error, isNull);
                expect(download.retryCount, 0);
                expect(download.bytesDownloaded, 0);
                expect(download.partialPath, isNull);
              }
            }
            expect(
              connection.requests.map((item) => item.requestId).toSet(),
              hasLength(3),
            );
            expect(
              connection.requests.every(
                (item) => item.requestId != 'old-request',
              ),
              isTrue,
            );
            if (resetAll) {
              expect(
                connection.requests.map((item) => item.clientId).toSet(),
                hasLength(3),
              );
            } else {
              expect(
                connection.requests.every(
                  (item) => item.clientId == oldClientId,
                ),
                isTrue,
              );
              expect(connection.freshManifests, 3);
            }
          } finally {
            await manager.dispose();
            await storage.close();
          }
        },
      );
    }
  }
}
