import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _origin = 'http://playlist.test/api';
const _source = SourceTrackRef(serverBaseUrl: _origin, serverTrackId: 'song');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late OfflineLibraryStorage storage;
  late _Connection connection;
  late OfflineDownloadManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite_playlist_workflow_');
    storage = OfflineLibraryStorage(baseDirectory: directory);
    connection = _Connection();
    manager = OfflineDownloadManager(connection: connection, storage: storage);
  });

  tearDown(() async {
    connection.batchGate?.completeIfPending(_manifest());
    await manager.dispose();
    await storage.close();
    await directory.delete(recursive: true);
  });

  Future<LocalPlaylistEntry> waitForStatus(String playlistId, OfflineDownloadStatus status) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final entries = await storage.readLocalPlaylistEntries(playlistId);

      if (entries.isNotEmpty && entries.single.status == status) return entries.single;

      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    throw StateError('Playlist did not reach $status');
  }

  Future<OfflineTrackDownload> failedSource() async {
    final partial = await storage.partialTrackFile(serverBaseUrl: _origin, trackId: 'song');

    await partial.writeAsBytes([1, 2, 3]);

    final download = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: _origin,
        track: offlineTestTrack(id: 'song'),
        status: OfflineDownloadStatus.failed,
      ).copyWith(partialPath: partial.path),
    );

    await storage.upsertDownload(download);

    return download;
  }

  test('save completes before metadata staging and failed staging retains membership', () async {
    final playlist = await manager.createLocalPlaylist('Mix');

    connection.setToken('token');
    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);

    expect(manager.localPlaylists.single.totalTrackCount, 1);
    expect(manager.localPlaylists.single.pendingTrackSources, [_source]);
    final failed = await waitForStatus(playlist.id, OfflineDownloadStatus.failed);
    expect(failed.isPlayable, isFalse);
    expect(failed.error, contains('offline'));
    await manager.loadLocalPlaylistTracks(playlist.id);
    expect(manager.localPlaylistEntries.single.entryKey, failed.entryKey);
    expect(manager.localPlaylistTracks, isEmpty);
  });

  test('deleting during metadata staging prevents a late response creating a download', () async {
    final playlist = await manager.createLocalPlaylist('Mix');

    connection.batchGate = Completer<DownloadBatchManifest>();
    connection.setToken('token');
    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await connection.batchStarted.future.timeout(const Duration(seconds: 3));
    await manager.removeLocalTrackFromPlaylist(playlist, offlineTestTrack(id: 'song'));
    connection.batchGate!.complete(_manifest());
    await manager.dispose();

    expect(await storage.readLocalPlaylistEntries(playlist.id), isEmpty);
    expect(await storage.readDownloads(), isEmpty);
    expect(await storage.readDownloadBatches(), isEmpty);
    expect(await storage.hasDownloadDemand(_source), isFalse);
  });

  test('removing the last unfinished playlist request removes failed partial data', () async {
    final download = await failedSource();
    final playlist = await manager.createLocalPlaylist('Mix');

    await manager.addSourceToLocalPlaylist(playlist.id, download.track, _source);
    await manager.removeLocalTrackFromPlaylist(playlist, download.track);

    expect(await storage.readLocalPlaylistEntries(playlist.id), isEmpty);
    expect(await storage.readDownloads(), isEmpty);
    expect(await File(download.partialPath!).exists(), isFalse);
  });

  test('two playlists share unfinished source and only the last removal cleans it', () async {
    final download = await failedSource();
    final first = await manager.createLocalPlaylist('First');
    final second = await manager.createLocalPlaylist('Second');

    await manager.addSourceToLocalPlaylist(first.id, download.track, _source);
    await manager.addSourceToLocalPlaylist(second.id, download.track, _source);
    await manager.removeLocalTrackFromPlaylist(first, download.track);

    expect(await File(download.partialPath!).exists(), isTrue);
    expect((await storage.readLocalPlaylistEntries(second.id)), hasLength(1));
    await manager.removeLocalTrackFromPlaylist(second, download.track);
    expect(await File(download.partialPath!).exists(), isFalse);
  });

  test('independent download demand survives playlist removal', () async {
    final download = await failedSource();
    final playlist = await manager.createLocalPlaylist('Mix');

    await storage.registerDownloadDemand(_source, ownerKind: 'manual', ownerId: 'manual-request');
    await manager.addSourceToLocalPlaylist(playlist.id, download.track, _source);
    await manager.removeLocalTrackFromPlaylist(playlist, download.track);

    expect(await File(download.partialPath!).exists(), isTrue);
    expect(await storage.readDownloads(), hasLength(1));
  });

  test('clear unfinished leaves canceled visible intent and does not requeue it on load', () async {
    final playlist = await manager.createLocalPlaylist('Mix');

    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await waitForStatus(playlist.id, OfflineDownloadStatus.paused);
    await manager.clearUnfinishedDownloads();
    await manager.load();

    expect((await storage.readLocalPlaylistEntries(playlist.id)).single.status, OfflineDownloadStatus.canceled);
    expect(connection.batchCalls, 0);
  });

  test('a switched server never receives the saved source track ID', () async {
    final playlist = await manager.createLocalPlaylist('Mix');

    connection.setBaseUrl('http://other.test/api');
    connection.setToken('token');
    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await waitForStatus(playlist.id, OfflineDownloadStatus.paused);

    expect(connection.batchCalls, 0);
    expect(manager.localPlaylists.single.pendingTrackSources, [_source]);
  });

  test('completed playlist removal retains verified media', () async {
    final file = await storage.trackFile(serverBaseUrl: _origin, trackId: 'song', extension: 'mp3');

    await file.writeAsBytes([1, 2, 3]);

    final download = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: _origin,
        track: offlineTestTrack(id: 'song'),
        filePath: file.path,
      ),
    );

    await storage.upsertDownload(download);

    final playlist = await manager.createLocalPlaylist('Complete');

    await manager.addSourceToLocalPlaylist(playlist.id, download.track, _source);
    await manager.removeLocalTrackFromPlaylist(playlist, download.track);

    expect(await storage.readLocalPlaylistEntries(playlist.id), isEmpty);
    expect(await file.exists(), isTrue);
    expect(await storage.readDownloads(), hasLength(1));
  });

  test('retry after clearing unfinished restores demand for the still-saved entry', () async {
    final playlist = await manager.createLocalPlaylist('Retry');

    await manager.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await waitForStatus(playlist.id, OfflineDownloadStatus.paused);
    await manager.clearUnfinishedDownloads();

    final entry = (await storage.readLocalPlaylistEntries(playlist.id)).single;

    connection.setToken('token');
    await manager.retryLocalPlaylistEntry(entry);
    await waitForStatus(playlist.id, OfflineDownloadStatus.failed);

    expect(connection.batchCalls, 1);
    expect(await storage.hasDownloadDemand(_source), isTrue);
  });
}

DownloadBatchManifest _manifest() => DownloadBatchManifest(
  schemaVersion: 1,
  batchId: 'batch',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  items: [
    DownloadBatchItem(
      trackId: 'song',
      downloadUrl: '/download/tracks/song',
      byteLength: 3,
      contentType: 'audio/mpeg',
      etag: 'song',
      sha256: '',
      offlineMetadata: offlineTestOfflineMetadata(trackId: 'song'),
    ),
  ],
  unavailable: [],
);

class _Connection extends ServerConnection {
  final batchStarted = Completer<void>();
  Completer<DownloadBatchManifest>? batchGate;
  int batchCalls = 0;

  _Connection() : super(baseUrl: _origin, client: MockClient((_) async => throw StateError('Unexpected network')));

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    batchCalls++;
    if (!batchStarted.isCompleted) batchStarted.complete();

    final gate = batchGate;
    if (gate != null) return gate.future;

    throw StateError('offline batch');
  }

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async => throw StateError('offline metadata');
}

extension on Completer<DownloadBatchManifest> {
  void completeIfPending(DownloadBatchManifest value) {
    if (!isCompleted) complete(value);
  }
}
