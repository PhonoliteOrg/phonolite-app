import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  const baseUrl = 'https://queued-downloads.invalid/api';
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  late Directory directory;
  late _SnapshotStorage storage;
  late ServerConnection connection;
  late OfflineDownloadManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite-job-item-snapshot-');
    storage = _SnapshotStorage(
      baseDirectory: Directory('${directory.path}/offline'),
      settingsStorage: OfflineStorageSettingsStorage(
        files: SettingsFiles(directoryProvider: () async => Directory('${directory.path}/settings')),
      ),
    );
    connection = ServerConnection(baseUrl: baseUrl);
    manager = OfflineDownloadManager(connection: connection, storage: storage);
  });

  tearDown(() async {
    await manager.dispose();
    connection.close();
    await storage.close();
    await directory.delete(recursive: true);
  });

  OfflineDownloadJob job(String id, {OfflineDownloadStatus status = OfflineDownloadStatus.paused}) =>
      OfflineDownloadJob(
        jobId: id,
        profile: 'opus_128',
        kind: 'album',
        serverBaseUrl: baseUrl,
        status: status,
        createdAt: now,
        updatedAt: now,
        totalCount: 1,
        discoveredCount: 1,
      );

  OfflineDownloadJobItem item(String jobId, {String trackId = 'song', int position = 0, bool materialized = false}) =>
      OfflineDownloadJobItem(
        jobId: jobId,
        position: position,
        serverTrackId: trackId,
        status: OfflineDownloadStatus.queued,
        materialized: materialized,
        createdAt: now,
        updatedAt: now,
        track: offlineTestTrack(id: trackId, title: 'Queued song'),
        offlineMetadata: offlineTestOfflineMetadata(trackId: trackId, trackTitle: 'Queued song'),
      );

  test('restored queued tracks are published before a transfer exists', () async {
    await storage.upsertDownloadJobs([job('pending'), job('canceled', status: OfflineDownloadStatus.canceled)]);
    await storage.upsertDownloadJobItems([item('pending'), item('canceled')]);

    final next = manager.downloadSnapshotStream.firstWhere((state) => state.jobItems.isNotEmpty);
    await manager.load();
    final state = await next.timeout(const Duration(seconds: 2));

    expect(state.downloads, isEmpty);
    expect(state.jobItems.single.jobId, 'pending');
    expect(state.jobItems.single.track!.title, 'Queued song');
    expect(state.jobItems.single.materialized, isFalse);
    expect(state.jobItems.single.offlineMetadata, isNull);
    expect(manager.downloadSnapshot.jobItems.single.track!.title, 'Queued song');
    expect(() => state.jobItems.clear(), throwsUnsupportedError);
    expect(() => manager.downloadSnapshot.jobItems.clear(), throwsUnsupportedError);
  });

  test('item title and error changes publish without changing job counts', () async {
    final original = item('pending');
    await storage.upsertDownloadJob(job('pending'));
    await storage.upsertDownloadJobItems([original]);
    final loaded = manager.downloadSnapshotStream.firstWhere((state) => state.jobItems.isNotEmpty);
    await manager.load();
    final initial = await loaded.timeout(const Duration(seconds: 2));

    final renamed = original.copyWith(track: original.track!.copyWith(title: 'Renamed queued song'));
    await storage.upsertDownloadJobItems([renamed]);
    final titleChange = manager.downloadSnapshotStream.firstWhere(
      (state) => state.jobItems.single.track?.title == 'Renamed queued song',
    );
    await manager.load();
    final renamedState = await titleChange.timeout(const Duration(seconds: 2));

    expect(renamedState.jobs.single.completedCount, initial.jobs.single.completedCount);
    expect(renamedState.jobs.single.updatedAt, initial.jobs.single.updatedAt);
    expect(renamedState.revision, greaterThan(initial.revision));

    await storage.upsertDownloadJobItems([renamed.copyWith(error: 'Waiting for source file')]);
    final errorChange = manager.downloadSnapshotStream.firstWhere(
      (state) => state.jobItems.single.error == 'Waiting for source file',
    );
    await manager.load();
    final errorState = await errorChange.timeout(const Duration(seconds: 2));

    expect(errorState.jobs.single.updatedAt, renamedState.jobs.single.updatedAt);
    expect(errorState.revision, greaterThan(renamedState.revision));
  });

  test('lean job reads retain only pending track labels and omit full metadata', () async {
    await storage.upsertDownloadJob(job('pending'));
    await storage.upsertDownloadJobItems([
      item('pending'),
      item('pending', trackId: 'materialized', position: 1, materialized: true),
    ]);

    final items = await storage.readDownloadJobItemsLean('pending');

    expect(items.first.track!.title, 'Queued song');
    expect(items.first.offlineMetadata, isNull);
    expect(items.last.track, isNull);
    expect(items.last.offlineMetadata, isNull);
  });

  test('snapshots omit materialized, completed and canceled job items', () async {
    await storage.upsertDownloadJob(job('pending').copyWith(totalCount: 4, discoveredCount: 4));
    await storage.upsertDownloadJobItems([
      item('pending'),
      item('pending', trackId: 'completed', position: 1).copyWith(status: OfflineDownloadStatus.downloaded),
      item('pending', trackId: 'canceled', position: 2).copyWith(status: OfflineDownloadStatus.canceled),
      item(
        'pending',
        trackId: 'materialized',
        position: 3,
        materialized: true,
      ).copyWith(status: OfflineDownloadStatus.failed),
    ]);
    await storage.upsertDownloads(
      await storage.prepareDownloads([
        offlineTestDownload(
          serverBaseUrl: baseUrl,
          batchId: 'pending',
          track: offlineTestTrack(id: 'materialized'),
          status: OfflineDownloadStatus.failed,
        ),
      ]),
    );

    final next = manager.downloadSnapshotStream.firstWhere((state) => state.jobItems.isNotEmpty);
    await manager.load();
    final state = await next.timeout(const Duration(seconds: 2));

    expect(state.downloads.single.track.id, 'materialized');
    expect(state.jobItems.single.serverTrackId, 'song');
    expect(() => state.jobItems.clear(), throwsUnsupportedError);
  });

  test('metadata-only track label changes publish without job or item changes', () async {
    final original = item('pending').copyWith(track: null);
    storage.jobItemsOverride = [original];
    await storage.upsertDownloadJob(job('pending'));
    final loaded = manager.downloadSnapshotStream.firstWhere((state) => state.jobItems.isNotEmpty);
    await manager.load();
    final initial = await loaded.timeout(const Duration(seconds: 2));

    storage.jobItemsOverride = [
      original.copyWith(
        offlineMetadata: offlineTestOfflineMetadata(trackId: 'song', trackTitle: 'Metadata-only queued song'),
      ),
    ];
    final changed = manager.downloadSnapshotStream.firstWhere(
      (state) => state.jobItems.single.offlineMetadata?.track.title == 'Metadata-only queued song',
    );
    await manager.load();
    final state = await changed.timeout(const Duration(seconds: 2));

    expect(state.jobItems.single.track, isNull);
    expect(state.jobs.single.updatedAt, initial.jobs.single.updatedAt);
    expect(state.jobItems.single.updatedAt, initial.jobItems.single.updatedAt);
    expect(state.revision, greaterThan(initial.revision));
  });

  test('unavailable queued tracks publish their failure and update the parent job', () async {
    await manager.dispose();
    connection.close();
    final unavailableConnection = _UnavailableConnection(baseUrl)..setToken('fixture-token');
    connection = unavailableConnection;
    manager = OfflineDownloadManager(connection: connection, storage: storage);
    await storage.upsertDownloadJob(job('pending').copyWith(profile: 'original'));
    await storage.upsertDownloadJobItems([item('pending')]);
    final loaded = manager.downloadSnapshotStream.firstWhere((state) => state.jobItems.isNotEmpty);
    await manager.load();
    await loaded.timeout(const Duration(seconds: 2));

    try {
      final queued = manager.downloadSnapshotStream.firstWhere(
        (state) => state.jobs.single.status == OfflineDownloadStatus.queued,
      );
      await manager.resumeDownloadJob(manager.jobs.single);
      await unavailableConnection.started.future.timeout(const Duration(seconds: 2));
      await queued.timeout(const Duration(seconds: 2));

      final failed = manager.downloadSnapshotStream.firstWhere(
        (state) =>
            state.jobItems.single.status == OfflineDownloadStatus.failed &&
            state.jobs.single.status == OfflineDownloadStatus.failed,
      );
      unavailableConnection.release.complete();
      final state = await failed.timeout(const Duration(seconds: 2));

      expect(state.downloads, isEmpty);
      expect(state.jobItems.single.error, 'unavailable');
      expect(state.jobs.single.failedCount, 1);
    } finally {
      if (!unavailableConnection.release.isCompleted) unavailableConnection.release.complete();
    }
  });
}

class _SnapshotStorage extends OfflineLibraryStorage {
  List<OfflineDownloadJobItem>? jobItemsOverride;

  _SnapshotStorage({required super.baseDirectory, required super.settingsStorage});

  @override
  Future<List<OfflineDownloadJobItem>> readDownloadJobItemsLean(String jobId) async {
    final override = jobItemsOverride;

    if (override != null) {
      return override.where((item) => item.jobId == jobId).toList(growable: false);
    }

    return super.readDownloadJobItemsLean(jobId);
  }
}

class _UnavailableConnection extends ServerConnection {
  final started = Completer<void>();
  final release = Completer<void>();

  _UnavailableConnection(String baseUrl)
    : super(baseUrl: baseUrl, client: MockClient((_) async => throw StateError('Unexpected HTTP request')));

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    if (!started.isCompleted) started.complete();
    await release.future;

    return DownloadBatchManifest(
      schemaVersion: 1,
      batchId: clientBatchId!,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      items: [],
      unavailable: [for (final id in trackIds) DownloadBatchUnavailable(trackId: id, reason: 'missing')],
    );
  }

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );
}
