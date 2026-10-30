import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  const base = 'https://inline.invalid/api';
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

  test('unfinished download updates keep the completed library and refresh lookups', () async {
    final file = await File('${root.path}/completed.mp3').writeAsBytes([1, 2, 3]);
    final prepared = await storage.prepareDownloads([
      offlineTestDownload(
        serverBaseUrl: base,
        track: offlineTestTrack(id: 'completed'),
        filePath: file.path,
      ),
      offlineTestDownload(
        serverBaseUrl: base,
        track: offlineTestTrack(id: 'pending', title: 'Pending Song'),
        status: OfflineDownloadStatus.queued,
      ).copyWith(bytesDownloaded: 400, bytesTotal: 1000),
    ]);
    await storage.upsertDownloads(prepared);
    final loaded = manager.librarySnapshotStream.firstWhere((snapshot) => snapshot.tracks.length == 1);
    await manager.load();
    await loaded.timeout(const Duration(seconds: 1));

    final completedTrack = manager.localDownloadedTracks().single;
    final libraryRevision = manager.librarySnapshot.revision;
    final pending = manager.findForCurrentServer('pending')!;
    final paused = manager.downloadSnapshotStream.firstWhere(
      (snapshot) => snapshot.downloads.any(
        (download) => download.track.id == 'pending' && download.status == OfflineDownloadStatus.paused,
      ),
    );

    await manager.pauseDownload(pending);
    final pauseState = await paused.timeout(const Duration(seconds: 1));
    final pausedDownload = manager.findForCurrentServer('pending')!;
    expect(pausedDownload.status, OfflineDownloadStatus.paused);
    expect(pausedDownload.updatedAt.isAfter(pending.updatedAt), isTrue);
    expect(pausedDownload.bytesDownloaded, 400);
    expect(pausedDownload.bytesTotal, 1000);
    expect(manager.findLocal(pausedDownload.localTrackId!), same(pausedDownload));
    expect(pauseState.downloads.singleWhere((download) => download.track.id == 'pending'), same(pausedDownload));
    // A new completed Track object would reveal a redundant full projection
    // rebuild even if snapshot equality suppressed the library notification.
    expect(manager.localDownloadedTracks().single, same(completedTrack));
    expect(manager.librarySnapshot.revision, libraryRevision);
    expect(() => manager.localDownloadedTracks().clear(), throwsUnsupportedError);

    await manager.resumeDownload(pausedDownload);
    expect(manager.findForCurrentServer('pending')!.status, OfflineDownloadStatus.queued);
    expect(manager.localDownloadedTracks().single, same(completedTrack));

    await manager.setLocalLike(completedTrack, true);
    expect(manager.localDownloadedTracks().single.liked, isTrue);
    final playlist = await manager.createLocalPlaylist('Saved');
    await manager.addLocalTrackToPlaylist(playlist, completedTrack);
    expect(manager.localDownloadedTracks().single.inPlaylists, isTrue);

    await manager.removeDownload(manager.findForCurrentServer('completed')!);
    expect(manager.localDownloadedTracks(), isEmpty);
    expect(manager.findForCurrentServer('pending')!.status, OfflineDownloadStatus.queued);
  });
}
