import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/persistence/settings_files.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  const base = 'https://inline.invalid/api/v1';
  late Directory root;
  late OfflineLibraryStorage storage;
  late OfflineDownloadManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inline-snapshot-');
    storage = OfflineLibraryStorage(
      baseDirectory: Directory('${root.path}/offline'),
      keepDatabaseOpen: true,
      settingsStorage: OfflineStorageSettingsStorage(
        files: SettingsFiles(
          directoryProvider: () async => Directory('${root.path}/settings'),
        ),
      ),
    );
    manager = OfflineDownloadManager(
      connection: ServerConnection(baseUrl: base),
      storage: storage,
    );
  });
  tearDown(() async {
    await manager.dispose();
    await storage.close();
    await root.delete(recursive: true);
  });

  test(
    'inline job pause and resume publish coherent download snapshots',
    () async {
      final now = DateTime.now();
      final track = offlineTestTrack(id: 'track');
      await storage.upsertDownloadJob(
        OfflineDownloadJob(
          jobId: 'job',
          kind: 'album',
          serverBaseUrl: base,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
        ),
      );
      await storage.upsertDownloadJobItems([
        OfflineDownloadJobItem(
          jobId: 'job',
          position: 0,
          serverTrackId: track.id,
          status: OfflineDownloadStatus.queued,
          materialized: true,
          createdAt: now,
          updatedAt: now,
          track: track,
        ),
      ]);
      await storage.upsertDownloads(
        await storage.prepareDownloads([
          offlineTestDownload(
            serverBaseUrl: base,
            batchId: 'job',
            track: track,
            status: OfflineDownloadStatus.queued,
          ),
        ]),
      );
      await manager.load();
      final paused = manager.downloadSnapshotStream.firstWhere(
        (s) => s.jobs.any((j) => j.status == OfflineDownloadStatus.paused),
      );
      await manager.pauseDownloadJob(manager.jobs.single);
      final pauseState = await paused.timeout(const Duration(seconds: 1));
      expect(pauseState.jobs.single.status, OfflineDownloadStatus.paused);
      final resumed = manager.downloadSnapshotStream.firstWhere(
        (s) => s.jobs.any(
          (j) =>
              j.status == OfflineDownloadStatus.queued ||
              j.status == OfflineDownloadStatus.downloading,
        ),
      );
      await manager.resumeDownloadJob(manager.jobs.single);
      final resumeState = await resumed.timeout(const Duration(seconds: 1));
      expect(resumeState.revision, greaterThan(pauseState.revision));
    },
  );

  test('inline playlist mutation publishes the library snapshot', () async {
    await manager.load();
    final next = manager.librarySnapshotStream.firstWhere(
      (s) => s.playlists.any((p) => p.name == 'Created'),
    );
    final playlist = await manager.createLocalPlaylist('Created');
    final state = await next.timeout(const Duration(seconds: 1));
    expect(state.playlists.single.id, playlist.id);
    expect(state.revision, greaterThan(0));
  });
}
