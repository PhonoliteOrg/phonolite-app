import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _origin = 'https://playlist-staging.test/api';
const _source = SourceTrackRef(serverBaseUrl: _origin, serverTrackId: 'song');

enum _PauseAt { batchSaved, tracksPrepared }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final pauseAt in _PauseAt.values) {
    test('removal during ${pauseAt.name} leaves no source or batch after staging settles', () async {
      final directory = await Directory.systemTemp.createTemp('phonolite_staging_remove_');
      final storage = _StagingStorage(directory, pauseAt);
      final connection = _Connection();
      final manager = OfflineDownloadManager(connection: connection, storage: storage);

      addTearDown(() async {
        if (!storage.release.isCompleted) {
          storage.release.complete();
        }

        await manager.dispose();
        await storage.close();
        await directory.delete(recursive: true);
      });

      final playlist = await manager.createLocalPlaylist('Mix');
      connection.setToken('token');
      await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
      await storage.paused.future.timeout(const Duration(seconds: 3));
      final removal = manager.removeLocalTrackFromPlaylist(playlist, offlineTestTrack(id: 'song'));
      storage.release.complete();
      await removal.timeout(const Duration(seconds: 3));

      expect(await storage.readLocalPlaylistEntries(playlist.id), isEmpty);
      expect(await storage.readDownloads(), isEmpty);
      expect(await storage.readDownloadBatches(), isEmpty);
      expect(await storage.hasDownloadDemand(_source), isFalse);
    });
  }

  test('full reset drains an in-flight saved intent before deleting its database', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite_intent_reset_');
    final storage = _DelayedIntentStorage(directory);
    final manager = OfflineDownloadManager(connection: _Connection(), storage: storage);

    addTearDown(() async {
      if (!storage.release.isCompleted) {
        storage.release.complete();
      }

      await manager.dispose();
      await storage.close();
      await directory.delete(recursive: true);
    });

    final playlist = await manager.createLocalPlaylist('Mix');
    final addition = manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    final settled = addition.then<Object?>((_) => null, onError: (Object error) => error);
    await storage.saved.future.timeout(const Duration(seconds: 3));
    final reset = manager.resetLocalData();
    await Future<void>.delayed(Duration.zero);
    storage.release.complete();
    await Future.wait([settled, reset]).timeout(const Duration(seconds: 15));

    expect(await storage.readLocalPlaylists(), isEmpty);
    expect(await storage.readPendingPlaylistEntries(), isEmpty);
    expect(await storage.readDownloadDemandSources(), isEmpty);
    expect(await storage.readDownloads(), isEmpty);
  });

  test('full reset drains a retry demand so it cannot survive its deleted playlist', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite_retry_reset_');
    final storage = _DelayedDemandStorage(directory);
    final manager = OfflineDownloadManager(connection: _Connection(), storage: storage);

    addTearDown(() async {
      if (!storage.release.isCompleted) {
        storage.release.complete();
      }

      await manager.dispose();
      await storage.close();
      await directory.delete(recursive: true);
    });

    final playlist = await manager.createLocalPlaylist('Mix');
    final entry = await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    final retry = manager.retryLocalPlaylistEntry(entry);
    final settled = retry.then<Object?>((_) => null, onError: (Object error) => error);
    await storage.saved.future.timeout(const Duration(seconds: 3));
    final reset = manager.resetLocalData();
    await Future<void>.delayed(Duration.zero);
    storage.release.complete();
    await Future.wait([settled, reset]).timeout(const Duration(seconds: 15));

    expect(await storage.readLocalPlaylists(), isEmpty);
    expect(await storage.readDownloadDemandSources(), isEmpty);
  });

  test('returning to the source server retries metadata after an obsolete request settles', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite_playlist_reconnect_');
    final storage = OfflineLibraryStorage(baseDirectory: directory);
    final connection = _ReconnectConnection();
    final manager = OfflineDownloadManager(connection: connection, storage: storage);

    addTearDown(() async {
      if (!connection.firstResponse.isCompleted) {
        connection.firstResponse.complete(offlineTestDownloadManifest(batchId: 'old-batch', trackId: 'song'));
      }

      await manager.dispose();
      await storage.close();
      await directory.delete(recursive: true);
    });

    final playlist = await manager.createLocalPlaylist('Mix');
    connection.setToken('source-token');
    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await connection.firstStarted.future.timeout(const Duration(seconds: 3));
    connection.setBaseUrl('https://another.test/api');
    connection.setToken('other-token');
    connection.setBaseUrl(_origin);
    connection.setToken('restored-source-token');
    await manager.resumePausedForCurrentServer();
    connection.firstResponse.complete(offlineTestDownloadManifest(batchId: 'old-batch', trackId: 'song'));
    await connection.replacementStarted.future.timeout(const Duration(seconds: 3));

    expect(connection.batchCalls, 2);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 1);
  });
}

class _StagingStorage extends OfflineLibraryStorage {
  final _PauseAt pauseAt;
  final Completer<void> paused = Completer<void>();
  final Completer<void> release = Completer<void>();

  _StagingStorage(Directory directory, this.pauseAt) : super(baseDirectory: directory);

  @override
  Future<void> upsertDownloadBatch(OfflineDownloadBatch batch) async {
    await super.upsertDownloadBatch(batch);

    if (pauseAt == _PauseAt.batchSaved && !paused.isCompleted) {
      paused.complete();
      await release.future;
    }
  }

  @override
  Future<List<OfflineTrackDownload>> prepareDownloads(List<OfflineTrackDownload> downloads) async {
    final result = await super.prepareDownloads(downloads);

    if (pauseAt == _PauseAt.tracksPrepared && !paused.isCompleted) {
      paused.complete();
      await release.future;
    }

    return result;
  }
}

class _Connection extends ServerConnection {
  _Connection() : super(baseUrl: _origin, client: MockClient((_) async => throw StateError('Unexpected transfer')));

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async =>
      offlineTestDownloadManifest(batchId: 'playlist-batch', trackId: trackIds.single);
}

class _DelayedIntentStorage extends OfflineLibraryStorage {
  final Completer<void> saved = Completer<void>();
  final Completer<void> release = Completer<void>();

  _DelayedIntentStorage(Directory directory) : super(baseDirectory: directory);

  @override
  Future<LocalPlaylistEntry> addSourceToLocalPlaylist(String playlistId, Track track, SourceTrackRef source) async {
    final result = await super.addSourceToLocalPlaylist(playlistId, track, source);
    saved.complete();
    await release.future;

    return result;
  }
}

class _DelayedDemandStorage extends OfflineLibraryStorage {
  final Completer<void> saved = Completer<void>();
  final Completer<void> release = Completer<void>();

  _DelayedDemandStorage(Directory directory) : super(baseDirectory: directory);

  @override
  Future<void> registerDownloadDemand(
    SourceTrackRef source, {
    required String ownerKind,
    required String ownerId,
  }) async {
    await super.registerDownloadDemand(source, ownerKind: ownerKind, ownerId: ownerId);
    saved.complete();
    await release.future;
  }
}

class _ReconnectConnection extends _Connection {
  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> replacementStarted = Completer<void>();
  final Completer<DownloadBatchManifest> firstResponse = Completer<DownloadBatchManifest>();
  int batchCalls = 0;

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    batchCalls++;

    if (batchCalls == 1) {
      firstStarted.complete();

      return firstResponse.future;
    }

    replacementStarted.complete();

    return offlineTestDownloadManifest(batchId: 'replacement-batch', trackId: trackIds.single);
  }
}
