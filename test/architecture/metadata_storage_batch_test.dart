import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/auth_test_helpers.dart';
import '../support/offline_library_test_helpers.dart';

const _server = 'https://server.test/api/v1';

class _CountingStorage extends OfflineLibraryStorage {
  _CountingStorage(Directory directory)
    : super(baseDirectory: directory, keepDatabaseOpen: true);

  final chunks = <int>[];

  @override
  Future<Set<String>> upsertOfflineMetadataFragments(
    String serverBaseUrl,
    Map<String, OfflineTrackMetadata> metadataByTrackId, {
    bool Function()? shouldPersist,
  }) {
    chunks.add(metadataByTrackId.length);
    return super.upsertOfflineMetadataFragments(
      serverBaseUrl,
      metadataByTrackId,
      shouldPersist: shouldPersist,
    );
  }
}

class _RepairConnection extends ServerConnection {
  _RepairConnection({this.release}) : super(baseUrl: _server) {
    setTrust(testServerTrust);
  }

  final Completer<void>? release;
  final requested = Completer<void>();
  int reads = 0;

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    reads++;
    if (!requested.isCompleted) requested.complete();
    if (release != null) await release!.future;
    return offlineTestOfflineMetadata(
      trackId: trackId,
      schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
    );
  }
}

class _ArtworkRefreshConnection extends ServerConnection {
  _ArtworkRefreshConnection() : super(baseUrl: _server) {
    setTrust(testServerTrust);
  }

  final oldArtworkRequested = Completer<void>();
  final releaseOldArtwork = Completer<void>();
  final replacementArtworkRequested = Completer<void>();
  int metadataReads = 0;

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    final composite = metadataReads++ == 0;
    return offlineTestOfflineMetadata(
      trackId: trackId,
      schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
      artistName: composite ? 'First, Second' : 'First',
      artistId: composite ? 'composite' : 'first',
    );
  }

  @override
  Future<ServerArtwork?> fetchAlbumCoverBytes(
    String albumId, {
    Duration timeout = const Duration(seconds: 8),
  }) async => null;

  @override
  Future<ServerArtwork?> fetchArtistCoverBytes(
    String artistId, {
    String kind = 'logo',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (artistId == 'composite') {
      if (!oldArtworkRequested.isCompleted) oldArtworkRequested.complete();
      await releaseOldArtwork.future;
      return ServerArtwork(bytes: [1, 2, 3], contentType: 'image/png');
    }
    if (kind == 'banner' && !replacementArtworkRequested.isCompleted) {
      replacementArtworkRequested.complete();
    }
    return null;
  }
}

Future<OfflineTrackDownload> _seedArtistArtwork(
  OfflineLibraryStorage storage,
  Directory directory, {
  String artistId = 'composite',
  String artistName = 'First, Second',
}) async {
  final prepared = await storage.prepareDownload(
    offlineTestDownload(
      serverBaseUrl: _server,
      track: offlineTestTrack(
        id: 'art-track',
        artist: artistName,
        artistId: artistId,
        albumArtPath: (await offlineTestMediaFile(
          directory,
          'album-art.png',
        )).path,
        artistArtPath: (await offlineTestMediaFile(
          directory,
          'artist-logo.png',
        )).path,
        artistBannerPath: (await offlineTestMediaFile(
          directory,
          'artist-banner.png',
        )).path,
      ),
      filePath: (await offlineTestMediaFile(directory, 'art-track.mp3')).path,
    ),
  );
  await storage.upsertDownload(prepared);
  return prepared;
}

Future<List<OfflineTrackDownload>> _seed(
  OfflineLibraryStorage storage,
  Directory directory, {
  int count = 2,
  String server = _server,
}) async {
  final downloads = <OfflineTrackDownload>[];
  for (var i = 0; i < count; i++) {
    downloads.add(
      offlineTestDownload(
        serverBaseUrl: server,
        track: offlineTestTrack(id: 'track-$i', title: 'Song $i'),
        filePath: (await offlineTestMediaFile(directory, '$i.mp3')).path,
      ),
    );
  }
  final prepared = await storage.prepareDownloads(downloads);
  await storage.upsertDownloads(prepared);
  return prepared;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _CountingStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'phonolite_metadata_batch_',
    );
    storage = _CountingStorage(directory);
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  test(
    'batch storage keeps source mappings and skips deleted sources',
    () async {
      final prepared = await _seed(storage, directory);
      final persisted = await storage.upsertOfflineMetadataFragments(_server, {
        'track-0': offlineTestOfflineMetadata(
          trackId: 'track-0',
          artistSummary: 'First artist.',
        ),
        'track-1': offlineTestOfflineMetadata(
          trackId: 'track-1',
          artistSummary: 'Second artist.',
        ),
        'deleted-track': offlineTestOfflineMetadata(trackId: 'deleted-track'),
      });
      expect(persisted, {'track-0', 'track-1'});
      final downloads = await storage.readDownloads();
      for (final download in downloads) {
        final id = download.track.serverTrackId;
        expect(download.serverBaseUrl, _server);
        expect(
          download.localTrackId,
          prepared.firstWhere((item) => item.track.id == id).localTrackId,
        );
        expect(download.offlineMetadata?.track.serverTrackId, id);
        expect(download.offlineMetadata?.track.serverBaseUrl, _server);
      }
      final otherSource = await storage
          .upsertOfflineMetadataFragments('https://other.test/api/v1', {
            'track-0': offlineTestOfflineMetadata(
              trackId: 'track-0',
              artistSummary: 'Wrong source.',
            ),
          });
      expect(otherSource, isEmpty);
      expect(
        (await storage.readDownloads()).first.offlineMetadata?.artist.summary,
        isNot('Wrong source.'),
      );
    },
  );

  test(
    'artist identity repair clears composite artwork and retains music',
    () async {
      final prepared = await _seedArtistArtwork(storage, directory);
      await storage.upsertOfflineMetadataFragment(
        _server,
        'art-track',
        offlineTestOfflineMetadata(
          trackId: 'art-track',
          artistName: 'First',
          artistId: 'first',
        ),
      );

      final download = (await storage.readDownloads()).single;
      final track = (await storage.readLocalDownloadedTracks()).single;
      for (final repaired in [download.track, track]) {
        expect(repaired.artistId, 'first');
        expect(repaired.artistArtPath, isNull);
        expect(repaired.artistBannerPath, isNull);
        expect(repaired.albumId, prepared.track.albumId);
        expect(repaired.albumArtPath, prepared.track.albumArtPath);
        expect(repaired.localId, prepared.localTrackId);
        expect(repaired.serverTrackId, 'art-track');
      }
      expect(download.localTrackId, prepared.localTrackId);
      expect(download.filePath, prepared.filePath);
      expect(await File(download.filePath!).readAsBytes(), [1, 2, 3]);

      await storage.updateTrackArtPaths(
        prepared.localTrackId!,
        artistArtPath: prepared.track.artistArtPath,
        artistBannerPath: prepared.track.artistBannerPath,
        artworkSource: prepared.track,
      );
      expect(
        (await storage.readDownloads()).single.track.artistArtPath,
        isNull,
      );
      expect(
        (await storage.readDownloads()).single.track.artistBannerPath,
        isNull,
      );
    },
  );

  test(
    'metadata refresh retains artwork for the same individual artist',
    () async {
      final prepared = await _seedArtistArtwork(
        storage,
        directory,
        artistId: 'first',
        artistName: 'First',
      );
      await storage.upsertOfflineMetadataFragment(
        _server,
        'art-track',
        offlineTestOfflineMetadata(
          trackId: 'art-track',
          artistName: 'Updated display name',
          artistId: 'first',
        ),
      );

      final track = (await storage.readDownloads()).single.track;
      expect(track.artistArtPath, prepared.track.artistArtPath);
      expect(track.artistBannerPath, prepared.track.artistBannerPath);
      expect(track.albumArtPath, prepared.track.albumArtPath);
    },
  );

  test(
    'new artist fragments never borrow a composite download portrait',
    () async {
      final prepared = await _seedArtistArtwork(storage, directory);
      await storage.upsertDownload(
        prepared.copyWith(
          offlineMetadata: offlineTestOfflineMetadata(
            trackId: 'art-track',
            artistName: 'First',
            artistId: 'first',
          ),
        ),
      );

      final download = (await storage.readDownloads()).single;
      expect(download.track.artistId, 'first');
      expect(download.track.credits.single.artistId, 'first');
      expect(
        (await storage.readLocalDownloadedTracks()).single.artistId,
        'first',
      );
      expect(download.track.artistArtPath, isNull);
      expect(download.track.artistBannerPath, isNull);
      expect(download.offlineMetadata?.track.artistArtPath, isNull);
      expect(download.offlineMetadata?.track.artistBannerPath, isNull);
      expect(download.track.albumArtPath, prepared.track.albumArtPath);
      expect(download.filePath, prepared.filePath);
    },
  );

  test(
    'late artwork hydration cannot replace a corrected individual profile',
    () async {
      final media = await offlineTestMediaFile(directory, 'late-art-track.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: _server,
          track: offlineTestTrack(
            id: 'late-art-track',
            artist: 'First, Second',
            artistId: 'composite',
          ),
          filePath: media.path,
        ),
      );
      await storage.upsertDownload(prepared);
      final connection = _ArtworkRefreshConnection();
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(() async {
        if (!connection.releaseOldArtwork.isCompleted) {
          connection.releaseOldArtwork.complete();
        }
        await manager.dispose();
      });
      await manager.load();
      connection.setToken('session');
      await manager.refreshOfflineMetadataForAlbum('album-1');
      await connection.oldArtworkRequested.future;
      await manager.refreshOfflineMetadataForAlbum('album-1');
      connection.releaseOldArtwork.complete();
      await connection.replacementArtworkRequested.future;

      for (final track in [
        manager.downloads.single.track,
        (await storage.readDownloads()).single.track,
      ]) {
        expect(track.artistId, 'first');
        expect(track.artistArtPath, isNull);
        expect(track.artistBannerPath, isNull);
        expect(track.localId, prepared.localTrackId);
      }
      expect(manager.downloads.single.filePath, media.path);
    },
  );

  test('a failed fragment rolls back the whole metadata chunk', () async {
    final prepared = await _seed(storage, directory);
    final db = sqlite3.open(
      offlineTestJoin(
        offlineTestJoin(directory.path, 'offline'),
        'phonolite_offline.sqlite',
      ),
    );
    addTearDown(db.dispose);
    db.execute('''
      CREATE TRIGGER reject_metadata BEFORE INSERT ON offline_metadata_fragments
      WHEN NEW.server_track_id = 'track-1'
      BEGIN SELECT RAISE(ABORT, 'test storage failure'); END
    ''');
    await expectLater(
      storage.upsertOfflineMetadataFragments(_server, {
        'track-0': offlineTestOfflineMetadata(
          trackId: 'track-0',
          trackTitle: 'Updated 0',
        ),
        'track-1': offlineTestOfflineMetadata(
          trackId: 'track-1',
          trackTitle: 'Updated 1',
        ),
      }),
      throwsA(isA<SqliteException>()),
    );
    expect(db.select('SELECT * FROM offline_metadata_fragments'), isEmpty);
    for (final download in await storage.readDownloads()) {
      expect(
        download.track.title,
        prepared
            .firstWhere((item) => item.track.id == download.track.id)
            .track
            .title,
      );
    }
  });

  test(
    'the final persistence guard cancels a stale session before writes',
    () async {
      await _seed(storage, directory);
      final persisted = await storage.upsertOfflineMetadataFragments(_server, {
        'track-0': offlineTestOfflineMetadata(trackId: 'track-0'),
      }, shouldPersist: () => false);
      expect(persisted, isEmpty);
      expect(
        (await storage.readDownloads()).every(
          (item) => item.offlineMetadata == null,
        ),
        true,
      );
    },
  );

  test('eight repaired tracks commit in two bounded chunks', () async {
    await _seed(storage, directory, count: 8);
    final connection = _RepairConnection();
    final manager = OfflineDownloadManager(
      connection: connection,
      storage: storage,
    );
    addTearDown(manager.dispose);
    await manager.load();
    connection.setToken('session');
    await manager.repairOfflineMetadataFragments();
    expect(connection.reads, 8);
    expect(storage.chunks, [4, 4]);
    expect(await storage.readMetadataRepairRequests(_server), isEmpty);
    await manager.repairOfflineMetadataFragments();
    expect(connection.reads, 8);
  });

  test(
    'changing credentials during repair discards fetched metadata',
    () async {
      await _seed(storage, directory, count: 4);
      final release = Completer<void>();
      final connection = _RepairConnection(release: release);
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      connection.setToken('old-session');
      final repair = manager.repairOfflineMetadataFragments();
      await connection.requested.future;
      connection.setToken('new-session');
      release.complete();
      await repair;
      expect(storage.chunks, isEmpty);
      expect((await storage.readMetadataRepairRequests(_server)).length, 4);
    },
  );
}
