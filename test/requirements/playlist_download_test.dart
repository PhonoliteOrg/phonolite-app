import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

const _baseUrl = 'http://server.test/api/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late OfflineLibraryStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'phonolite_playlist_copy_',
    );
    storage = OfflineLibraryStorage(baseDirectory: directory);
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  Future<OfflineTrackDownload> complete(
    String id, {
    String baseUrl = _baseUrl,
  }) async {
    final file = await offlineTestMediaFile(directory, '$id.mp3');
    final download = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: baseUrl,
        track: offlineTestTrack(id: id, title: id),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(download);
    return download;
  }

  test(
    'copies artwork, metadata, order and repetitions without redownloading',
    () async {
      final a = await complete('a');
      final b = await complete('b');
      final connection = _PlaylistConnection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      final server = Playlist(
        id: 'server-playlist',
        name: 'Server mix',
        description: 'Server description',
        imageRef: 'cover-v1',
        trackIds: ['b', 'a', 'b'],
      );

      final local = await manager.downloadPlaylist(
        server,
        [a.track, b.track],
        name: server.name,
        description: server.description,
      );

      expect(local.id, isNot(server.id));
      expect(local.name, server.name);
      expect(local.description, server.description);
      expect(local.trackIds, [b.localTrackId, a.localTrackId, b.localTrackId]);
      expect(
        (await storage.readLocalPlaylistTracks(local.id)).map((t) => t.title),
        ['b', 'a', 'b'],
      );
      expect(await File(local.imagePath!).readAsBytes(), [1, 2, 3]);
      expect(connection.coverRequests, ['server-playlist:cover-v1']);
      expect(connection.batchRequests, isEmpty);
      expect(manager.localPlaylists.single.id, local.id);
      expect(server.trackIds, ['b', 'a', 'b']);
      expect(server.imagePath, isNull);
    },
  );

  test('custom metadata and artwork replace the server defaults', () async {
    final connection = _PlaylistConnection();
    final manager = OfflineDownloadManager(
      connection: connection,
      storage: storage,
    );
    addTearDown(manager.dispose);
    final local = await manager.downloadPlaylist(
      Playlist(
        id: 'empty',
        name: 'Original',
        description: 'Original description',
        imageRef: 'cover',
        trackIds: [],
      ),
      [],
      name: 'My local mix',
      description: 'My description',
      imageEdit: PlaylistImageEdit.replace(
        bytes: Uint8List.fromList([4, 5, 6]),
        contentType: 'image/png',
      ),
    );
    expect(local.name, 'My local mix');
    expect(local.description, 'My description');
    expect(local.trackIds, isEmpty);
    expect(await File(local.imagePath!).readAsBytes(), [4, 5, 6]);
    expect(connection.coverRequests, isEmpty);
    expect(connection.batchRequests, isEmpty);
  });

  test('queues only missing playlist tracks, using their exact IDs', () async {
    final b = await complete('b');
    final connection = _PlaylistConnection()..setToken('token');
    final manager = OfflineDownloadManager(
      connection: connection,
      storage: storage,
    );
    addTearDown(manager.dispose);
    final local = await manager.downloadPlaylist(
      Playlist(id: 'mix', name: 'Mix', trackIds: ['c', 'b', 'a', 'c']),
      [
        offlineTestTrack(id: 'a', title: 'a'),
        b.track,
        offlineTestTrack(id: 'c', title: 'c'),
        offlineTestTrack(id: 'unrelated'),
      ],
      name: 'Local mix',
    );
    expect(connection.batchRequests, [
      ['c', 'a'],
    ]);
    expect(local.trackIds, [b.localTrackId]);
    expect(manager.jobs.single.kind, 'playlist');

    await complete('a');
    await complete('c');
    await manager.loadLocalPlaylists();
    expect(
      (await storage.readLocalPlaylistTracks(local.id)).map((t) => t.title),
      ['c', 'b', 'a', 'c'],
    );
    expect(manager.localPlaylists.single.trackIds, hasLength(4));
    expect((await storage.readDownloads()).map((d) => d.track.id).toSet(), {
      'a',
      'b',
      'c',
    });
  });

  test(
    'pending order survives a restart and reserves space before manual additions',
    () async {
      final local = await storage.createLocalPlaylist(
        'Pending mix',
        downloadServerBaseUrl: _baseUrl,
        downloadTrackIds: ['a', 'b', 'a'],
      );
      await complete('b');
      final extra = await complete('extra');
      await storage.addLocalTrackToPlaylist(local.id, extra.localTrackId!);
      await storage.close();
      storage = OfflineLibraryStorage(baseDirectory: directory);
      await complete('a');

      expect(
        (await storage.readLocalPlaylistTracks(local.id)).map((t) => t.title),
        ['a', 'b', 'a', 'extra'],
      );
      // Manual additions retain the existing behavior of avoiding duplicates.
      await storage.addLocalTrackToPlaylist(local.id, extra.localTrackId!);
      expect((await storage.readLocalPlaylistTracks(local.id)), hasLength(4));
    },
  );

  test(
    'pending memberships use the original server and disappear on deletion',
    () async {
      final local = await storage.createLocalPlaylist(
        'Scoped mix',
        downloadServerBaseUrl: _baseUrl,
        downloadTrackIds: ['a'],
      );
      await complete('a', baseUrl: 'http://other.test/api/v1');
      expect(await storage.readLocalPlaylistTracks(local.id), isEmpty);
      await storage.deleteLocalPlaylist(local.id);
      await complete('a');
      expect(await storage.readLocalPlaylists(), isEmpty);
      final db = sqlite3.open(
        offlineTestJoin(
          offlineTestJoin(directory.path, 'offline'),
          'phonolite_offline.sqlite',
        ),
      );
      try {
        expect(db.select('SELECT * FROM pending_playlist_tracks'), isEmpty);
      } finally {
        db.dispose();
      }
    },
  );

  test(
    'upgrades old playlist membership schema without changing existing order',
    () async {
      final a = await complete('a');
      final b = await complete('b');
      final local = await storage.createLocalPlaylist('Existing');
      await storage.addLocalTrackToPlaylist(local.id, b.localTrackId!);
      await storage.addLocalTrackToPlaylist(local.id, a.localTrackId!);
      await storage.close();
      final db = sqlite3.open(
        offlineTestJoin(
          offlineTestJoin(directory.path, 'offline'),
          'phonolite_offline.sqlite',
        ),
      );
      try {
        db.execute(
          'ALTER TABLE local_playlist_tracks RENAME TO old_memberships',
        );
        db.execute('''CREATE TABLE local_playlist_tracks (
        playlist_id TEXT NOT NULL, local_track_id TEXT NOT NULL, position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, local_track_id),
        FOREIGN KEY (playlist_id) REFERENCES local_playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (local_track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )''');
        db.execute(
          'INSERT INTO local_playlist_tracks SELECT * FROM old_memberships',
        );
        db.execute('DROP TABLE old_memberships');
        db.execute(
          "UPDATE metadata SET value = '10' WHERE key = 'schema_version'",
        );
      } finally {
        db.dispose();
      }
      storage = OfflineLibraryStorage(baseDirectory: directory);
      expect((await storage.readLocalPlaylists()).single.trackIds, [
        b.localTrackId,
        a.localTrackId,
      ]);
      final copy = await storage.createLocalPlaylist(
        'Repeated copy',
        downloadServerBaseUrl: _baseUrl,
        downloadTrackIds: ['a', 'b', 'a'],
      );
      expect(copy.trackIds, [a.localTrackId, b.localTrackId, a.localTrackId]);
    },
  );

  test(
    'missing artwork or track metadata leaves no partial local playlist',
    () async {
      final connection = _PlaylistConnection()..artworkAvailable = false;
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await expectLater(
        manager.downloadPlaylist(
          Playlist(id: 'mix', name: 'Mix', imageRef: 'missing', trackIds: []),
          [],
          name: 'Copy',
        ),
        throwsStateError,
      );
      await expectLater(
        manager.downloadPlaylist(
          Playlist(id: 'mix', name: 'Mix', trackIds: ['missing']),
          [],
          name: 'Copy',
        ),
        throwsStateError,
      );
      expect(await storage.readLocalPlaylists(), isEmpty);
      expect(connection.batchRequests, isEmpty);
    },
  );

  test(
    'playlist artwork fetch authenticates and uses the versioned cover URL',
    () async {
      final connection = ServerConnection(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            '$_baseUrl/library/playlists/my%20mix/cover?v=cover-v2',
          );
          expect(request.url.queryParameters['v'], 'cover-v2');
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response.bytes(
            [7, 8, 9],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      )..setToken('test-token');
      final art = await connection.fetchPlaylistCoverBytes(
        'my mix',
        imageRef: 'cover-v2',
      );
      expect(art?.bytes, [7, 8, 9]);
      expect(art?.contentType, 'image/png');
    },
  );
}

class _PlaylistConnection extends ServerConnection {
  _PlaylistConnection() : super(baseUrl: _baseUrl);
  final batchRequests = <List<String>>[];
  final coverRequests = <String>[];
  bool artworkAvailable = true;

  @override
  Future<ServerArtwork?> fetchPlaylistCoverBytes(
    String playlistId, {
    String? imageRef,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    coverRequests.add('$playlistId:$imageRef');
    return artworkAvailable
        ? ServerArtwork(bytes: [1, 2, 3], contentType: 'image/png')
        : null;
  }

  @override
  Future<ServerCapabilities> fetchCapabilities() async => ServerCapabilities(
    downloadJobsV2: false,
    metadataSnapshotsV2: false,
    eventReplayV2: false,
    trackFileContractV2: false,
  );

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    batchRequests.add(List.of(trackIds));
    // Headless verification only: queue the tracks without opening media requests.
    setToken(null);
    return DownloadBatchManifest(
      schemaVersion: 1,
      batchId: clientBatchId ?? 'batch',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      items: [
        for (final id in trackIds)
          DownloadBatchItem(
            trackId: id,
            downloadUrl: '/download/tracks/$id',
            byteLength: 3,
            contentType: 'audio/mpeg',
            etag: id,
            sha256: '',
            offlineMetadata: offlineTestOfflineMetadata(
              trackId: id,
              trackTitle: id,
            ),
          ),
      ],
      unavailable: [],
    );
  }
}
