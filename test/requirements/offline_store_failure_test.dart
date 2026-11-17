import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

/// Failed is not empty: offline storage reports a read or write it could not complete instead of answering with an
/// empty result or a silent success. Failures are injected into a real library database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverBaseUrl = 'http://server-one.test/api';
  final now = DateTime.fromMillisecondsSinceEpoch(5);

  late Directory temp;
  late OfflineLibraryStorage storage;

  String databasePath() => offlineTestJoin(offlineTestJoin(temp.path, 'offline'), 'phonolite_offline.sqlite');

  void execute(String sql) {
    final db = sqlite3.open(databasePath());

    try {
      db.execute(sql);
    } finally {
      db.dispose();
    }
  }

  /// Makes every read of [table] fail until [restoreTable] runs.
  void hideTable(String table) => execute('ALTER TABLE $table RENAME TO ${table}_hidden');

  void restoreTable(String table) => execute('ALTER TABLE ${table}_hidden RENAME TO $table');

  /// Makes every insert, update and delete on [table] fail, as a full disk or a locked database would.
  void rejectWrites(String table) {
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      execute(
        "CREATE TRIGGER reject_${event.toLowerCase()}_$table BEFORE $event ON $table "
        "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END",
      );
    }
  }

  OfflineDownloadBatch batch() => OfflineDownloadBatch(
    batchId: 'batch-1',
    serverBaseUrl: serverBaseUrl,
    status: OfflineDownloadStatus.queued,
    createdAt: now,
    updatedAt: now,
    totalCount: 1,
  );

  OfflineDownloadJob job() => OfflineDownloadJob(
    jobId: 'job-1',
    kind: 'album',
    serverBaseUrl: serverBaseUrl,
    status: OfflineDownloadStatus.queued,
    createdAt: now,
    updatedAt: now,
  );

  OfflineDownloadJobItem jobItem() => OfflineDownloadJobItem(
    jobId: 'job-1',
    position: 0,
    serverTrackId: 'server-track-1',
    status: OfflineDownloadStatus.queued,
    materialized: false,
    createdAt: now,
    updatedAt: now,
  );

  OfflineDownloadJobSource jobSource() => OfflineDownloadJobSource(
    jobId: 'job-1',
    position: 0,
    sourceId: 'album-1',
    status: OfflineDownloadStatus.queued,
    createdAt: now,
    updatedAt: now,
  );

  Future<OfflineTrackDownload> savedDownload() async {
    final file = await offlineTestMediaFile(temp, 'track.mp3');
    final download = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: serverBaseUrl,
        track: offlineTestTrack(id: 'server-track-1'),
        filePath: file.path,
      ),
    );

    await storage.upsertDownload(download);

    return download;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phonolite_offline_store_failure_');
    storage = OfflineLibraryStorage(baseDirectory: temp);

    // Creates the schema, so later injections act on an initialized library.
    await storage.readDownloads();
  });

  tearDown(() => temp.delete(recursive: true));

  group('failed reads are not empty results', () {
    final reads = <String, (String, Future<Object?> Function(OfflineLibraryStorage storage))>{
      'downloads': ('source_tracks', (storage) => storage.readDownloads()),
      'download batches': ('download_batches', (storage) => storage.readDownloadBatches()),
      'download jobs': ('download_jobs', (storage) => storage.readDownloadJobs()),
      'download job items': ('download_job_items', (storage) => storage.readDownloadJobItems('job-1')),
      'lean download job items': ('download_job_items', (storage) => storage.readDownloadJobItemsLean('job-1')),
      'download job sources': ('download_job_sources', (storage) => storage.readDownloadJobSources('job-1')),
      'local liked tracks': ('local_likes', (storage) => storage.readLocalLikedTracks()),
      'local like states': ('local_like_states', (storage) => storage.readLocalLikeStates()),
      'local playlists': ('local_playlists', (storage) => storage.readLocalPlaylists()),
      'local playlist tracks': ('local_playlist_tracks', (storage) => storage.readLocalPlaylistTracks('playlist-1')),
      'local downloaded tracks': ('source_tracks', (storage) => storage.readLocalDownloadedTracks()),
      'metadata repair queue': ('source_tracks', (storage) => storage.readMetadataRepairRequests(serverBaseUrl)),
      'pending file deletes': ('pending_file_deletes', (storage) => storage.readPendingFileDeletes()),
    };

    for (final MapEntry(key: name, value: (table, read)) in reads.entries) {
      test('reading $name reports an unreadable table', () async {
        hideTable(table);

        await expectLater(read(storage), throwsA(isA<SqliteException>()));

        restoreTable(table);

        await expectLater(read(storage), completes);
      });
    }
  });

  group('failed writes and deletes are reported', () {
    test('download batch upsert and delete', () async {
      await storage.upsertDownloadBatch(batch());
      rejectWrites('download_batches');

      await expectLater(storage.upsertDownloadBatch(batch()), throwsA(isA<SqliteException>()));
      await expectLater(storage.deleteDownloadBatch('batch-1'), throwsA(isA<SqliteException>()));
      expect(await storage.readDownloadBatches(), hasLength(1));
    });

    test('download job upserts and delete', () async {
      await storage.upsertDownloadJob(job());
      await storage.upsertDownloadJobItems([jobItem()]);
      await storage.upsertDownloadJobSources([jobSource()]);
      rejectWrites('download_jobs');
      rejectWrites('download_job_items');
      rejectWrites('download_job_sources');

      await expectLater(storage.upsertDownloadJob(job()), throwsA(isA<SqliteException>()));
      await expectLater(storage.upsertDownloadJobs([job()]), throwsA(isA<SqliteException>()));
      await expectLater(storage.upsertDownloadJobItems([jobItem()]), throwsA(isA<SqliteException>()));
      await expectLater(storage.upsertDownloadJobSources([jobSource()]), throwsA(isA<SqliteException>()));
      await expectLater(storage.deleteDownloadJob('job-1'), throwsA(isA<SqliteException>()));
      expect(await storage.readDownloadJobs(), hasLength(1));
      expect(await storage.readDownloadJobItems('job-1'), hasLength(1));
      expect(await storage.readDownloadJobSources('job-1'), hasLength(1));
    });

    test('download upserts and library writes', () async {
      final download = await savedDownload();
      rejectWrites('source_tracks');

      await expectLater(storage.upsertDownload(download), throwsA(isA<SqliteException>()));
      await expectLater(storage.upsertDownloads([download]), throwsA(isA<SqliteException>()));
      await expectLater(storage.writeDownloads(const []), throwsA(isA<SqliteException>()));
      expect(await storage.readDownloads(), hasLength(1));
    });

    test('artwork path updates', () async {
      final download = await savedDownload();
      final art = await storage.albumArtFile(albumId: 'album-1', extension: 'png');
      await art.writeAsBytes(<int>[1, 2, 3]);
      rejectWrites('tracks');

      await expectLater(
        storage.updateTrackArtPaths(download.localTrackId!, albumArtPath: art.path),
        throwsA(isA<SqliteException>()),
      );
    });

    test('pending file delete records and clears', () async {
      final file = await storage.trackFile(serverBaseUrl: serverBaseUrl, trackId: 'server-track-2', extension: 'mp3');
      await storage.recordPendingFileDeletes([file.path]);
      rejectWrites('pending_file_deletes');

      await expectLater(storage.recordPendingFileDeletes([file.path]), throwsA(isA<SqliteException>()));
      await expectLater(storage.clearPendingFileDeletes([file.path]), throwsA(isA<SqliteException>()));
      expect(await storage.readPendingFileDeletes(), hasLength(1));
    });
  });

  group('offline download manager', () {
    test('download jobs that cannot be read fail the load instead of loading as none', () async {
      await storage.saveDownloadPlan(
        job: job().copyWith(status: OfflineDownloadStatus.paused),
        batch: batch(),
      );
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(manager.dispose);
      hideTable('download_jobs');

      await expectLater(manager.load(), throwsA(anything));
      expect(manager.jobs, isEmpty);

      restoreTable('download_jobs');
      await manager.load();

      expect(manager.jobs.map((job) => job.jobId), ['job-1']);
    });

    test('resetting local data recovers a library that cannot be opened', () async {
      await savedDownload();
      await File(databasePath()).writeAsBytes(List<int>.filled(4096, 7));
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(manager.dispose);

      await expectLater(manager.load(), throwsA(anything));
      await manager.resetLocalData();

      expect(await storage.readDownloads(), isEmpty);
      await manager.load();
      expect(manager.downloads, isEmpty);
    });
  });
}
