import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/downloads/download_quality.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/models/server/download_job_v2.dart';
import 'package:phonolite_app/data/models/server/server_capabilities.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _origin = 'https://quality.test:3000/api';

class _QualityConnection extends ServerConnection {
  final createdProfiles = <String>[];
  final fetchedJobs = <String>[];
  final actions = <String>[];
  bool supported = true;
  bool ready = false;
  bool wrongProfile = false;
  int legacyRequests = 0;
  String client = '';
  String profile = '';
  String request = '';
  Completer<void>? createGate;
  final creationStarted = Completer<void>();

  _QualityConnection()
    : super(baseUrl: _origin, client: MockClient((_) async => throw StateError('Unexpected HTTP request'))) {
    setToken('fixture-token');
  }

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: true,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: true,
    downloadProfiles: supported ? const ['original', 'opus_64', 'opus_96', 'opus_128', 'opus_192'] : const ['original'],
  );

  @override
  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
    String profile = 'original',
  }) async {
    createdProfiles.add(profile);
    client = clientId;
    request = clientRequestId;
    this.profile = profile;
    if (!creationStarted.isCompleted) creationStarted.complete();
    await createGate?.future;
    return _job();
  }

  @override
  Future<DownloadJobV2> fetchDownloadJob(String jobId) async {
    fetchedJobs.add(jobId);
    return _job();
  }

  DownloadJobV2 _job() {
    final now = DateTime.now();
    final metadata = offlineTestOfflineMetadata(trackId: 'song', trackTitle: 'Song');
    return DownloadJobV2(
      jobId: 'remote-job',
      clientId: client,
      clientRequestId: request,
      profile: wrongProfile ? 'original' : profile,
      scope: DownloadJobScopeV2(kind: 'track', id: 'song'),
      status: ready ? 'ready_to_download' : 'queued',
      createdAt: now,
      updatedAt: now,
      totalCount: 1,
      readyCount: ready ? 1 : 0,
      completedCount: 0,
      failedCount: 0,
      eventCursor: 1,
      items: [
        DownloadJobItemV2(
          position: 0,
          trackId: 'song',
          profile: profile,
          renditionId: 'source-revision-$profile',
          status: ready ? 'ready_to_download' : 'queued',
          offlineMetadata: metadata,
          downloadUrl: ready ? '/api/download/jobs/remote-job/tracks/song/file?rendition_id=$profile' : null,
          byteLength: ready ? 1234 : null,
          contentType: 'audio/ogg; codecs=opus',
          etag: '"rendition-$profile"',
          sha256: List.filled(64, 'a').join(),
        ),
      ],
    );
  }

  @override
  Future<DownloadBatchManifest> createDownloadBatch(List<String> trackIds, {String? clientBatchId}) async {
    legacyRequests++;
    throw StateError('Compressed downloads must not fall back to Original');
  }

  @override
  Future<void> applyDownloadJobAction({required String jobId, required String action}) async {
    actions.add('$jobId:$action');
  }
}

/// Stop before scheduling any transport worker; all tests remain listener-free.
class _PlanningStorage extends OfflineLibraryStorage {
  final _QualityConnection connection;
  Completer<void>? partialGate;
  int preparedBatches = 0;

  _PlanningStorage(Directory directory, this.connection) : super(baseDirectory: directory);

  @override
  Future<List<OfflineTrackDownload>> prepareDownloads(List<OfflineTrackDownload> downloads) async {
    preparedBatches++;
    connection.setToken(null);
    return super.prepareDownloads(downloads);
  }

  @override
  Future<File> partialTrackFile({required String serverBaseUrl, required String trackId}) async {
    await partialGate?.future;
    return super.partialTrackFile(serverBaseUrl: serverBaseUrl, trackId: trackId);
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for the download plan');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download API sends the profile and reads the prepared rendition contract', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/server/capabilities')) {
        return http.Response(
          jsonEncode({
            'download_jobs_v2': true,
            'download_profiles': ['original', 'opus_64'],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'job_id': 'job/id',
          'profile': 'opus_64',
          'items': [
            {
              'track_id': 'song',
              'profile': 'opus_64',
              'rendition_id': 'encoded-revision',
              'status': 'ready_to_download',
              'download_url': '/api/download/jobs/job%2Fid/tracks/song/file',
              'byte_length': 1234,
              'content_type': 'audio/ogg; codecs=opus',
              'etag': '"version"',
              'sha256': List.filled(64, 'a').join(),
            },
          ],
        }),
        200,
      );
    });
    final api = ServerConnection(baseUrl: _origin, client: transport)..setToken('token');
    addTearDown(api.close);
    final capabilities = await api.fetchCapabilities();
    expect(capabilities.downloadProfiles, ['original', 'opus_64']);
    final created = await api.createDownloadJob(
      clientId: 'device',
      clientRequestId: 'request',
      scope: DownloadJobScopeV2(kind: 'track', id: 'song'),
      profile: 'opus_64',
    );
    final loaded = await api.fetchDownloadJob(created.jobId);
    expect(jsonDecode(requests[1].body)['profile'], 'opus_64');
    expect(requests[2].url.toString(), '$_origin/download/jobs/job%2Fid');
    expect(loaded.profile, 'opus_64');
    expect(loaded.items.single.renditionId, 'encoded-revision');
    expect(loaded.items.single.byteLength, 1234);
    expect(requests.every((request) => request.headers['Authorization'] == 'Bearer token'), isTrue);
  });

  late Directory directory;
  late _QualityConnection connection;
  late _PlanningStorage storage;
  final managers = <OfflineDownloadManager>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite-quality-pipeline-');
    connection = _QualityConnection();
    storage = _PlanningStorage(directory, connection);
  });

  tearDown(() async {
    connection.setToken(null);
    if (storage.partialGate case final gate? when !gate.isCompleted) gate.complete();
    if (connection.createGate case final gate? when !gate.isCompleted) gate.complete();
    for (final manager in managers) {
      await manager.dispose();
    }
    managers.clear();
    connection.close();
    await storage.close();
    await directory.delete(recursive: true);
  });

  OfflineDownloadManager manager(Future<DownloadQuality> Function() provider) {
    final result = OfflineDownloadManager(connection: connection, storage: storage, qualityProvider: provider);
    managers.add(result);
    return result;
  }

  test('captures quality on the durable intent and preserves it across restart', () async {
    var preference = DownloadQuality.spaceSaver;
    final first = manager(() async => preference);
    await first.queueTracks([offlineTestTrack(id: 'song')]);
    await _until(() => first.jobs.isNotEmpty && first.jobs.single.serverJobId != null);
    preference = DownloadQuality.veryHigh;

    final saved = (await storage.readDownloadJobs()).single;
    expect(saved.profile, 'opus_64');
    expect(saved.serverJobId, 'remote-job');
    expect(connection.createdProfiles, ['opus_64']);

    await first.dispose();
    managers.remove(first);
    connection.ready = true;
    final restored = manager(() async => preference);
    await restored.load();
    await _until(() => restored.downloads.isNotEmpty);

    final download = restored.downloads.single;
    expect(download.profile, 'opus_64');
    expect(download.renditionId, 'source-revision-opus_64');
    expect(download.bytesTotal, 1234);
    expect(download.contentType, 'audio/ogg; codecs=opus');
    expect(download.downloadUrl, contains('/jobs/remote-job/'));
    expect(connection.createdProfiles, ['opus_64']);
    expect(connection.fetchedJobs, contains('remote-job'));
    expect(connection.legacyRequests, 0);
    expect((await storage.readDownloads()).single.profile, 'opus_64');
  });

  for (final quality in DownloadQuality.values.where((value) => !value.isOriginal)) {
    test('${quality.wireValue} stages only its prepared rendition', () async {
      connection.ready = true;
      final downloads = manager(() async => quality);
      await downloads.queueTracks([offlineTestTrack(id: 'song')]);
      await _until(() => downloads.downloads.isNotEmpty);
      expect(downloads.downloads.single.profile, quality.wireValue);
      expect(downloads.downloads.single.renditionId, 'source-revision-${quality.wireValue}');
      expect(downloads.downloads.single.expectedSha256, List.filled(64, 'a').join());
      expect(connection.createdProfiles, [quality.wireValue]);
      expect(connection.legacyRequests, 0);
    });
  }

  test('unsupported compressed profile fails clearly without Original fallback', () async {
    connection.supported = false;
    final downloads = manager(() async => DownloadQuality.high);
    await downloads.downloadTrack(offlineTestTrack(id: 'song'));
    await _until(() => downloads.jobs.any((job) => job.status == OfflineDownloadStatus.failed));

    expect(downloads.jobs.single.error, contains('Choose Original or update the server'));
    expect(downloads.downloads, isEmpty);
    expect(connection.createdProfiles, isEmpty);
    expect(connection.legacyRequests, 0);
    expect((await storage.readDownloadJobs()).single.profile, 'opus_128');
  });

  test('mismatched server profile cannot stage a file', () async {
    connection.wrongProfile = true;
    connection.ready = true;
    final downloads = manager(() async => DownloadQuality.standard);
    await downloads.queueTracks([offlineTestTrack(id: 'song')]);
    await _until(() => downloads.jobs.any((job) => job.status == OfflineDownloadStatus.failed));
    expect(downloads.jobs.single.error, contains('different download profile'));
    expect(downloads.downloads, isEmpty);
    expect(connection.legacyRequests, 0);
  });

  test('canceling an intent while preparation is in flight cannot resurrect it', () async {
    connection.createGate = Completer<void>();
    final downloads = manager(() async => DownloadQuality.high);
    await downloads.queueTracks([offlineTestTrack(id: 'song')]);
    await connection.creationStarted.future;
    await downloads.cancelDownloadJob(downloads.jobs.single);
    connection.createGate!.complete();
    await _until(() => connection.actions.contains('remote-job:cancel'));

    expect(downloads.jobs, isEmpty);
    expect(downloads.downloads, isEmpty);
    expect(await storage.readDownloadJobs(), isEmpty);
  });

  test('pausing while creation is in flight retains the remote ID for resume', () async {
    connection.createGate = Completer<void>();
    final downloads = manager(() async => DownloadQuality.high);
    await downloads.queueTracks([offlineTestTrack(id: 'song')]);
    await connection.creationStarted.future;
    await downloads.pauseDownloadJob(downloads.jobs.single);
    connection.createGate!.complete();
    await _until(() => connection.actions.contains('remote-job:pause'));

    expect(downloads.jobs.single.status, OfflineDownloadStatus.paused);
    expect(downloads.jobs.single.serverJobId, 'remote-job');
    expect((await storage.readDownloadJobs()).single.serverJobId, 'remote-job');
    await downloads.resumeDownloadJob(downloads.jobs.single);
    await _until(() => connection.fetchedJobs.isNotEmpty);
    expect(connection.createdProfiles, ['opus_128']);
    expect(connection.actions, contains('remote-job:resume'));
  });

  test('overlapping preparation cannot replace another active source rendition', () async {
    connection.createGate = Completer<void>();
    connection.ready = true;
    final downloads = manager(() async => DownloadQuality.veryHigh);
    await downloads.queueTracks([offlineTestTrack(id: 'song')]);
    await connection.creationStarted.future;
    final now = DateTime.now();
    await storage.upsertDownload(
      OfflineTrackDownload(
        serverBaseUrl: _origin,
        batchId: 'first-job',
        profile: 'opus_64',
        renditionId: 'first-rendition',
        downloadUrl: '/api/download/jobs/first/tracks/song/file',
        track: offlineTestTrack(id: 'song'),
        status: OfflineDownloadStatus.queued,
        createdAt: now,
        updatedAt: now,
      ),
    );
    storage.partialGate = Completer<void>();
    await downloads.load();
    await _until(() => downloads.downloads.single.status == OfflineDownloadStatus.preparing);
    connection.createGate!.complete();
    await _until(() => downloads.jobs.single.serverJobId == 'remote-job');
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(downloads.downloads.single.profile, 'opus_64');
    expect(downloads.downloads.single.batchId, 'first-job');
    expect(storage.preparedBatches, 0);
    expect(downloads.jobs.single.profile, 'opus_192');
    connection.setToken(null);
    storage.partialGate!.complete();
  });

  test('legacy records remain Original and playlist intents retain their first quality', () async {
    final now = DateTime.now();
    await storage.upsertDownload(
      offlineTestDownload(
        serverBaseUrl: _origin,
        track: offlineTestTrack(id: 'legacy'),
      ),
    );
    await storage.upsertDownloadJob(
      OfflineDownloadJob(
        jobId: 'legacy-job',
        kind: 'tracks',
        serverBaseUrl: _origin,
        status: OfflineDownloadStatus.paused,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect((await storage.readDownloads()).single.profile, 'original');
    expect((await storage.readDownloadJobs()).single.profile, 'original');
    const source = SourceTrackRef(serverBaseUrl: _origin, serverTrackId: 'pending');
    await storage.saveDownloadProfileIntent(source, 'opus_64');
    await storage.registerDownloadDemand(source, ownerKind: 'playlist', ownerId: 'playlist:1');
    await storage.saveDownloadProfileIntent(source, 'opus_192');
    expect(await storage.readDownloadProfileIntent(source), 'opus_64');
  });

  test('schema upgrade retains Original files, local identity, likes and playlists', () async {
    final file = await storage.trackFile(serverBaseUrl: _origin, trackId: 'legacy', extension: 'mp3');
    await file.writeAsBytes([1, 2, 3]);
    await storage.upsertDownload(
      offlineTestDownload(
        serverBaseUrl: _origin,
        track: offlineTestTrack(id: 'legacy'),
        filePath: file.path,
      ),
    );
    final before = (await storage.readDownloads()).single;
    await storage.setLocalLike(before.localTrackId!, true);
    final playlist = await storage.createLocalPlaylist('Keep me');
    await storage.addLocalTrackToPlaylist(playlist.id, before.localTrackId!);
    final metadata = await storage.metadataRoot();
    final database = sqlite3.open('${metadata.path}${Platform.pathSeparator}phonolite_offline.sqlite');
    try {
      for (final table in ['source_tracks', 'download_items']) {
        database.execute('ALTER TABLE $table DROP COLUMN profile');
        database.execute('ALTER TABLE $table DROP COLUMN rendition_id');
      }
      database.execute('ALTER TABLE download_jobs DROP COLUMN profile');
      database.execute('ALTER TABLE download_jobs DROP COLUMN server_job_id');
      database.execute("UPDATE metadata SET value = '12' WHERE key = 'schema_version'");
    } finally {
      database.dispose();
    }

    final after = (await storage.readDownloads()).single;
    expect(after.profile, 'original');
    expect(after.renditionId, isNull);
    expect(after.filePath, file.path);
    expect(after.localTrackId, before.localTrackId);
    expect(after.track.liked, isTrue);
    expect((await storage.readLocalPlaylists()).single.trackIds, contains(before.localTrackId));
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('compressed recovery cannot adopt an Original file with the same track ID', () async {
    final original = await storage.trackFile(serverBaseUrl: _origin, trackId: 'song', extension: 'opus');
    await original.writeAsBytes([1, 2, 3]);
    final now = DateTime.now();
    await storage.upsertDownload(
      OfflineTrackDownload(
        serverBaseUrl: _origin,
        track: offlineTestTrack(id: 'song'),
        profile: 'opus_64',
        renditionId: 'compressed-revision',
        contentType: 'audio/opus',
        status: OfflineDownloadStatus.downloaded,
        createdAt: now,
        updatedAt: now,
      ),
    );
    connection.setToken(null);
    final downloads = manager(() async => DownloadQuality.spaceSaver);
    await downloads.load();
    expect(downloads.downloads.single.status, OfflineDownloadStatus.corrupt);
    expect(downloads.downloads.single.filePath, isNull);
    expect(await original.exists(), isTrue);
  });
}
