import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/auth_test_helpers.dart';
import '../support/offline_library_test_helpers.dart';

const _server = 'https://recovery.test:3000/api/v1';
const _jobId = '92fd40d2-5d72-4c00-b228-ed595abcd130';
const _bytes = [1, 2, 3];

OfflineTrackMetadata _metadata(int index) => offlineTestOfflineMetadata(
  trackId: 'track-$index',
  trackTitle: 'Track $index',
  artistName: 'Jamiroquai',
);

class _Connection extends ServerConnection {
  _Connection()
    : super(
        baseUrl: _server,
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      ) {
    setTrust(testServerTrust);
  }

  final requestedAlbums = <String>[];
  int batchRequests = 0;

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    requestedAlbums.add(albumId);
    final albumNumber = int.parse(albumId.split('-').last);
    return [
      for (var index = 1; index <= 103; index++)
        if ((index - 1) % 7 + 1 == albumNumber) _metadata(index).track,
    ];
  }

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    batchRequests++;
    throw StateError('Completed tracks must not be downloaded again');
  }

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async =>
      _metadata(int.parse(trackId.split('-').last));

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

Future<File> _seedStalledArtist(OfflineLibraryStorage storage) async {
  final downloads = <OfflineTrackDownload>[];
  final items = <OfflineDownloadJobItem>[];
  final now = DateTime.now();
  final checksum = sha256.convert(_bytes).toString();
  late File partial;
  for (var index = 1; index <= 103; index++) {
    final metadata = _metadata(index);
    final failed = index == 65;
    final file = failed
        ? await storage.partialTrackFile(
            serverBaseUrl: _server,
            trackId: metadata.track.id,
          )
        : await storage.trackFile(
            serverBaseUrl: _server,
            trackId: metadata.track.id,
          );
    await file.writeAsBytes(_bytes);
    if (failed) partial = file;
    downloads.add(
      offlineTestDownload(
        serverBaseUrl: _server,
        batchId: _jobId,
        track: metadata.track,
        status: failed
            ? OfflineDownloadStatus.failed
            : OfflineDownloadStatus.downloaded,
        filePath: failed ? null : file.path,
      ).copyWith(
        offlineMetadata: metadata,
        partialPath: failed ? file.path : null,
        bytesDownloaded: 3,
        bytesTotal: 3,
        expectedSha256: checksum,
        contentType: 'audio/flac',
        error: failed ? 'Exception: ApiException(416)' : null,
        retryCount: failed ? 2 : 0,
      ),
    );
    // Match the reported state: 64 finished items, one failed full partial,
    // and 38 items marked unstaged even though their files are downloaded.
    items.add(
      OfflineDownloadJobItem(
        jobId: _jobId,
        position: index - 1,
        serverTrackId: metadata.track.id,
        status: index <= 64
            ? OfflineDownloadStatus.downloaded
            : failed
            ? OfflineDownloadStatus.failed
            : OfflineDownloadStatus.queued,
        materialized: index <= 65,
        createdAt: now,
        updatedAt: now,
        track: metadata.track,
      ),
    );
  }
  await storage.upsertDownloads(await storage.prepareDownloads(downloads));
  await storage.saveDownloadPlan(
    batch: OfflineDownloadBatch(
      batchId: _jobId,
      serverBaseUrl: _server,
      status: OfflineDownloadStatus.downloading,
      createdAt: now,
      updatedAt: now,
      totalCount: 103,
      completedCount: 64,
      failedCount: 1,
    ),
    job: OfflineDownloadJob(
      jobId: _jobId,
      kind: 'artist',
      serverBaseUrl: _server,
      sourceId: 'jamiroquai',
      label: 'Jamiroquai',
      status: OfflineDownloadStatus.downloading,
      createdAt: now,
      updatedAt: now,
      totalCount: 103,
      discoveredCount: 103,
      completedCount: 64,
      failedCount: 1,
      materializedCount: 65,
    ),
    items: items,
    sources: [
      for (var index = 1; index <= 7; index++)
        OfflineDownloadJobSource(
          jobId: _jobId,
          position: index - 1,
          sourceId: 'album-$index',
          status: OfflineDownloadStatus.queued,
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
    'restart repairs 64/103 stale progress and finalizes the complete partial',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_stalled_artist_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: root);
      final partial = await _seedStalledArtist(storage);
      final connection = _Connection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      try {
        await manager.load();
        expect(manager.jobs.single.completedCount, 102);
        expect(manager.jobs.single.materializedCount, 103);
        final repaired = await storage.readDownloadJobItems(_jobId);
        expect(repaired.where((item) => !item.materialized), isEmpty);
        expect(
          repaired.where(
            (item) => item.status == OfflineDownloadStatus.downloaded,
          ),
          hasLength(102),
        );
        connection.setToken('restored-session');
        await manager.resumePausedForCurrentServer();
        await offlineTestWaitFor(
          () =>
              manager.jobs.isEmpty &&
              manager.downloads.every((item) => item.isDownloaded),
        );
        expect(manager.downloads, hasLength(103));
        expect(connection.batchRequests, 0);
        expect(connection.requestedAlbums, hasLength(7));
        expect(await partial.exists(), isFalse);
        final finished = manager.findForCurrentServer('track-65')!;
        expect(finished.error, isNull);
        expect(finished.partialPath, isNull);
        expect(await File(finished.filePath!).readAsBytes(), _bytes);
        expect(await storage.readDownloadJobs(), isEmpty);
      } finally {
        await manager.dispose();
        await storage.close();
      }
    },
  );

  for (final valid in [true, false]) {
    test(
      'a full partial is ${valid ? 'promoted' : 'rejected'} after checksum validation',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'phonolite_complete_partial_',
        );
        addTearDown(() => root.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: root);
        final partial = await storage.partialTrackFile(
          serverBaseUrl: _server,
          trackId: 'track-1',
        );
        await partial.writeAsBytes(_bytes);
        await storage.upsertDownload(
          await storage.prepareDownload(
            offlineTestDownload(
              serverBaseUrl: _server,
              track: _metadata(1).track,
              status: OfflineDownloadStatus.validating,
            ).copyWith(
              offlineMetadata: _metadata(1),
              partialPath: partial.path,
              bytesDownloaded: 1,
              bytesTotal: 3,
              contentType: 'audio/flac',
              expectedSha256: sha256
                  .convert(valid ? _bytes : [3, 2, 1])
                  .toString(),
            ),
          ),
        );
        final connection = _Connection()..setToken('saved-session');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        try {
          await manager.load();
          final expectedStatus = valid
              ? OfflineDownloadStatus.downloaded
              : OfflineDownloadStatus.corrupt;
          await offlineTestWaitFor(
            () => manager.downloads.single.status == expectedStatus,
          );
          expect(await partial.exists(), isFalse);
          if (valid) {
            expect(
              await File(manager.downloads.single.filePath!).readAsBytes(),
              _bytes,
            );
            expect(manager.downloads.single.bytesDownloaded, 3);
          } else {
            expect(
              manager.downloads.single.error,
              contains('checksum mismatch'),
            );
            expect(manager.downloads.single.filePath, isNull);
          }
        } finally {
          await manager.dispose();
          await storage.close();
        }
      },
    );
  }
}
