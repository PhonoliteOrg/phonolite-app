import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_download_manager.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/offline_library_views.dart';
import 'package:phonolite_app/entities/server_connection.dart';

void main() {
  group('offline library sqlite behavior', () {
    test('migrates legacy JSON downloads into sqlite on first read', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_json_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final root = Directory(_join(temp.path, 'offline'));
      await root.create(recursive: true);
      final mediaFile = File(_join(root.path, 'track.mp3'));
      await mediaFile.writeAsBytes(<int>[1, 2, 3]);

      final legacy = OfflineTrackDownload(
        serverBaseUrl: 'http://server-one.test/api/v1',
        track: _track(id: 'server-track-1'),
        status: OfflineDownloadStatus.downloaded,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
        filePath: mediaFile.path,
        bytesDownloaded: 3,
        bytesTotal: 3,
      );
      await File(_join(root.path, 'offline_library.json')).writeAsString(
        jsonEncode({
          'downloads': [legacy.toJson()],
        }),
      );

      final downloads = await storage.readDownloads();

      expect(downloads, hasLength(1));
      expect(downloads.single.track.id, 'server-track-1');
      expect(downloads.single.localTrackId, startsWith('lt_'));
      expect(
        await File(_join(root.path, 'phonolite_offline.sqlite')).exists(),
        isTrue,
      );
    });

    test('merges matching metadata from different server sources', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_merge_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);

      final fileOne = await _mediaFile(temp, 'one.mp3');
      final first = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-one-track', durationMs: 180000),
          filePath: fileOne.path,
        ),
      );
      await storage.upsertDownload(first);

      final fileTwo = await _mediaFile(temp, 'two.mp3');
      final second = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-two.test/api/v1',
          track: _track(
            id: 'server-two-track',
            title: 'The Song!',
            durationMs: 181900,
          ),
          filePath: fileTwo.path,
        ),
      );
      await storage.upsertDownload(second);

      final downloads = await storage.readDownloads();
      final localIds = downloads.map((item) => item.localTrackId).toSet();
      final localTracks = await storage.readLocalDownloadedTracks();

      expect(downloads, hasLength(2));
      expect(localIds, hasLength(1));
      expect(localTracks, hasLength(1));
      expect(localTracks.single.serverTrackId, isNotEmpty);
    });

    test(
      'requires completed downloads for local likes and playlists',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_local_user_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);

        final queued = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'queued-track'),
            status: OfflineDownloadStatus.queued,
          ),
        );
        await storage.upsertDownload(queued);
        final localTrackId = queued.localTrackId!;
        final playlist = await storage.createLocalPlaylist('Local Mix');

        expect(
          () => storage.setLocalLike(localTrackId, true),
          throwsA(isA<StateError>()),
        );
        expect(
          () => storage.addLocalTrackToPlaylist(playlist.id, localTrackId),
          throwsA(isA<StateError>()),
        );

        final mediaFile = await _mediaFile(temp, 'completed.mp3');
        await storage.upsertDownload(
          queued.copyWith(
            status: OfflineDownloadStatus.downloaded,
            filePath: mediaFile.path,
            bytesDownloaded: 3,
            bytesTotal: 3,
          ),
        );

        await storage.setLocalLike(localTrackId, true);
        await storage.addLocalTrackToPlaylist(playlist.id, localTrackId);

        final liked = await storage.readLocalLikedTracks();
        final playlistTracks = await storage.readLocalPlaylistTracks(
          playlist.id,
        );
        final playlists = await storage.readLocalPlaylists();

        expect(liked.map((track) => track.localId), <String>[localTrackId]);
        expect(playlistTracks.map((track) => track.localId), <String>[
          localTrackId,
        ]);
        expect(playlists.single.trackIds, <String>[localTrackId]);
      },
    );

    test('stores local playlist images as managed artwork', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_playlist_image_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final playlist = await storage.createLocalPlaylist(
        'Cover Mix',
        description: 'Initial playlist summary.',
      );

      expect(playlist.description, 'Initial playlist summary.');

      final updated = await storage.updateLocalPlaylistImage(
        playlist.id,
        PlaylistImageEdit.replace(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          contentType: 'image/png',
        ),
      );

      expect(updated?.imagePath, isNotNull);
      final imageFile = File(updated!.imagePath!);
      expect(await imageFile.exists(), isTrue);
      expect(await imageFile.readAsBytes(), <int>[1, 2, 3]);
      expect(
        (await storage.readLocalPlaylists()).single.imagePath,
        imageFile.path,
      );
      expect(
        (await storage.readLocalPlaylists()).single.description,
        'Initial playlist summary.',
      );

      final renamed = await storage.renameLocalPlaylist(
        playlist.id,
        'Renamed Mix',
        description: 'Updated playlist summary.',
      );
      expect(renamed?.description, 'Updated playlist summary.');

      final cleared = await storage.updateLocalPlaylistImage(
        playlist.id,
        const PlaylistImageEdit.clear(),
      );

      expect(cleared?.imagePath, isNull);
      expect(await imageFile.exists(), isFalse);

      final replaced = await storage.updateLocalPlaylistImage(
        playlist.id,
        PlaylistImageEdit.replace(
          bytes: Uint8List.fromList(<int>[4, 5, 6]),
          contentType: 'image/jpeg',
        ),
      );
      final replacementFile = File(replaced!.imagePath!);
      expect(await replacementFile.exists(), isTrue);

      await storage.deleteLocalPlaylist(playlist.id);

      expect(await replacementFile.exists(), isFalse);
      expect(await storage.readLocalPlaylists(), isEmpty);
    });

    test('records local like and unlike history', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_like_state_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final mediaFile = await _mediaFile(temp, 'completed.mp3');
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-track-1'),
          filePath: mediaFile.path,
        ),
      );
      await storage.upsertDownload(prepared);
      final localTrackId = prepared.localTrackId!;

      await storage.setLocalLike(localTrackId, true);
      final likedState = (await storage.readLocalLikeStates()).single;

      expect(likedState.localTrackId, localTrackId);
      expect(likedState.liked, isTrue);
      expect(likedState.updatedAt, greaterThan(0));
      expect(await storage.readLocalLikedTracks(), hasLength(1));

      await storage.setLocalLike(localTrackId, false);
      final unlikedState = (await storage.readLocalLikeStates()).single;

      expect(unlikedState.localTrackId, localTrackId);
      expect(unlikedState.liked, isFalse);
      expect(
        unlikedState.updatedAt,
        greaterThanOrEqualTo(likedState.updatedAt),
      );
      expect(await storage.readLocalLikedTracks(), isEmpty);
    });

    test('orders local liked tracks by most recent like first', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_like_order_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final alphaFile = await _mediaFile(temp, 'alpha.mp3');
      final zetaFile = await _mediaFile(temp, 'zeta.mp3');
      final alpha = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(
            id: 'server-alpha',
            title: 'Alpha Song',
            durationMs: 180000,
          ),
          filePath: alphaFile.path,
        ),
      );
      final zeta = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(
            id: 'server-zeta',
            title: 'Zeta Song',
            durationMs: 181000,
          ),
          filePath: zetaFile.path,
        ),
      );
      await storage.upsertDownload(alpha);
      await storage.upsertDownload(zeta);

      await storage.setLocalLike(alpha.localTrackId!, true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await storage.setLocalLike(zeta.localTrackId!, true);

      final liked = await storage.readLocalLikedTracks();

      expect(liked.map((track) => track.title), <String>[
        'Zeta Song',
        'Alpha Song',
      ]);
    });

    test('persists server like sync baselines per server', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_like_sync_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final mediaFile = await _mediaFile(temp, 'completed.mp3');
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-track-1'),
          filePath: mediaFile.path,
        ),
      );
      await storage.upsertDownload(prepared);
      final localTrackId = prepared.localTrackId!;

      await storage.upsertServerLikeSyncs([
        ServerLikeSync(
          localTrackId: localTrackId,
          serverBaseUrl: 'http://server-one.test/api/v1',
          serverTrackId: 'server-track-1',
          matchConfidence: 1,
          matchKind: 'exact_server_track_id',
          lastLocalLiked: true,
          lastLocalUpdatedAt: 10,
          lastServerLiked: true,
          lastServerUpdatedAt: 20,
          syncedAt: 30,
        ),
        ServerLikeSync(
          localTrackId: localTrackId,
          serverBaseUrl: 'http://server-two.test/api/v1',
          serverTrackId: 'server-track-2',
          matchConfidence: 0.96,
          matchKind: 'metadata_strict',
          lastLocalLiked: false,
          lastLocalUpdatedAt: 40,
          lastServerLiked: false,
          lastServerUpdatedAt: 50,
          syncedAt: 60,
        ),
      ]);

      final first = await storage.readServerLikeSyncs(
        'http://server-one.test/api/v1',
      );
      final second = await storage.readServerLikeSyncs(
        'http://server-two.test/api/v1',
      );

      expect(first.single.serverTrackId, 'server-track-1');
      expect(first.single.lastServerUpdatedAt, 20);
      expect(second.single.serverTrackId, 'server-track-2');
      expect(second.single.matchKind, 'metadata_strict');
    });

    test(
      'keeps metadata and download roots independently configurable',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_split_roots_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final metadataDir = Directory(_join(temp.path, 'metadata'));
        final downloadsDir = Directory(_join(temp.path, 'downloads'));
        final storage = OfflineLibraryStorage(
          metadataDirectory: metadataDir,
          downloadsDirectory: downloadsDir,
        );

        final mediaPath = await storage.trackFile(
          serverBaseUrl: 'http://server-one.test/api/v1',
          trackId: 'server-track-1',
          extension: 'mp3',
        );
        final prepared = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'server-track-1'),
            filePath: mediaPath.path,
          ),
        );
        await storage.upsertDownload(prepared);

        expect(mediaPath.path.startsWith(downloadsDir.absolute.path), isTrue);
        expect(
          await File(
            _join(metadataDir.absolute.path, 'phonolite_offline.sqlite'),
          ).exists(),
          isTrue,
        );
      },
    );

    test(
      'full reset removes offline database artwork and media files',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_full_reset_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final metadataDir = Directory(_join(temp.path, 'metadata'));
        final downloadsDir = Directory(_join(temp.path, 'downloads'));
        final storage = OfflineLibraryStorage(
          metadataDirectory: metadataDir,
          downloadsDirectory: downloadsDir,
        );

        final mediaFile = await storage.trackFile(
          serverBaseUrl: 'http://server-one.test/api/v1',
          trackId: 'server-track-1',
          extension: 'mp3',
        );
        await mediaFile.writeAsBytes(<int>[1, 2, 3]);
        final albumArt = await storage.albumArtFile(
          albumId: 'album-1',
          extension: 'png',
        );
        await albumArt.writeAsBytes(<int>[4, 5, 6]);
        final artistArt = await storage.artistArtFile(
          artistId: 'artist-1',
          kind: 'logo',
          extension: 'png',
        );
        await artistArt.writeAsBytes(<int>[7, 8, 9]);
        final legacyIndex = File(
          _join(metadataDir.path, 'offline_library.json'),
        );
        await legacyIndex.writeAsString('{}');
        final walFile = File(
          _join(metadataDir.path, 'phonolite_offline.sqlite-wal'),
        );
        await walFile.writeAsString('');

        final prepared = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'server-track-1'),
            status: OfflineDownloadStatus.downloaded,
            filePath: mediaFile.path,
          ),
        );
        await storage.upsertDownload(prepared);
        await storage.setLocalLike(prepared.localTrackId!, true);
        final playlist = await storage.createLocalPlaylist('Offline');
        await storage.addLocalTrackToPlaylist(
          playlist.id,
          prepared.localTrackId!,
        );
        final databaseFile = File(
          _join(metadataDir.path, 'phonolite_offline.sqlite'),
        );

        expect(await databaseFile.exists(), isTrue);
        expect(await mediaFile.exists(), isTrue);
        expect(await albumArt.exists(), isTrue);
        expect(await artistArt.exists(), isTrue);
        expect(await legacyIndex.exists(), isTrue);
        expect(await walFile.exists(), isTrue);

        await storage.resetLocalData();

        expect(await databaseFile.exists(), isFalse);
        expect(await legacyIndex.exists(), isFalse);
        expect(await walFile.exists(), isFalse);
        expect(await mediaFile.exists(), isFalse);
        expect(await albumArt.exists(), isFalse);
        expect(await artistArt.exists(), isFalse);
        expect(await storage.readDownloads(), isEmpty);
        expect(await storage.readLocalDownloadedTracks(), isEmpty);
        expect(await storage.readLocalLikedTracks(), isEmpty);
        expect(await storage.readLocalPlaylists(), isEmpty);
      },
    );

    test('persists batch and item validation state', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_batch_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final now = DateTime.fromMillisecondsSinceEpoch(5);
      await storage.upsertDownloadBatch(
        OfflineDownloadBatch(
          batchId: 'batch-1',
          serverBaseUrl: 'http://server-one.test/api/v1',
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 1,
          label: 'Album',
        ),
      );
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-track-1'),
          status: OfflineDownloadStatus.paused,
        ).copyWith(
          batchId: 'batch-1',
          bytesTotal: 30,
          etag: '"track-1-30"',
          expectedSha256:
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          retryCount: 2,
          priority: 4,
        ),
      );
      await storage.upsertDownload(prepared);

      final batches = await storage.readDownloadBatches();
      final downloads = await storage.readDownloads();

      expect(batches.single.batchId, 'batch-1');
      expect(batches.single.label, 'Album');
      expect(downloads.single.batchId, 'batch-1');
      expect(downloads.single.status, OfflineDownloadStatus.paused);
      expect(downloads.single.expectedSha256, startsWith('ba7816'));
      expect(downloads.single.retryCount, 2);
      expect(downloads.single.priority, 4);
    });

    test('persists full offline metadata fragments for local views', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_full_metadata_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final mediaFile = await _mediaFile(temp, 'metadata.mp3');
      final metadata = _offlineMetadata(
        trackId: 'server-track-1',
        trackTitle: 'Angel',
        albumTitle: 'Mezzanine',
        albumSummary: 'A dark, heavy album summary.',
        artistName: 'Massive Attack',
        artistSummary: 'A Bristol collective summary.',
      );

      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: metadata.track,
          filePath: mediaFile.path,
        ).copyWith(offlineMetadata: metadata),
      );
      await storage.upsertDownload(prepared);

      final downloads = await storage.readDownloads();
      final localTracks = await storage.readLocalDownloadedTracks();
      final groups = offlineArtistGroups(localTracks);

      expect(downloads.single.offlineMetadata?.album.summary, contains('dark'));
      expect(
        downloads.single.track.offlineArtist?.summary,
        contains('Bristol'),
      );
      expect(localTracks.single.offlineAlbum?.year, 1998);
      expect(groups.single.toArtist().albumCount, 1);
      expect(groups.single.toArtist().genres, contains('trip hop'));
      expect(groups.single.albums.single.toAlbum().trackCount, 1);
      expect(groups.single.albums.single.toAlbum().summary, contains('dark'));
    });

    test(
      'local artist albums sort by release year before title fallback',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_album_year_sort_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        const serverBaseUrl = 'http://server-one.test/api/v1';
        final albums = <OfflineTrackMetadata>[
          _offlineMetadata(
            trackId: 'server-track-1',
            albumTitle: 'Cracker Island',
            albumId: 'album-2023',
            albumYear: 2023,
          ),
          _offlineMetadata(
            trackId: 'server-track-2',
            albumTitle: 'Demon Days',
            albumId: 'album-2005',
            albumYear: 2005,
          ),
          _offlineMetadata(
            trackId: 'server-track-3',
            albumTitle: 'A No Year Album',
            albumId: 'album-no-year',
            albumYear: null,
          ),
        ];
        for (final metadata in albums) {
          final prepared = await storage.prepareDownload(
            _download(
              serverBaseUrl: serverBaseUrl,
              track: metadata.track,
              filePath: (await _mediaFile(
                temp,
                '${metadata.track.id}.mp3',
              )).path,
            ).copyWith(offlineMetadata: metadata),
          );
          await storage.upsertDownload(prepared);
        }

        final groups = offlineArtistGroups(
          await storage.readLocalDownloadedTracks(),
        );

        expect(groups.single.albums.map((album) => album.title), <String>[
          'Demon Days',
          'Cracker Island',
          'A No Year Album',
        ]);
      },
    );

    test(
      'persists track genres and uses them in local fallback groups',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_track_genres_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final mediaFile = await _mediaFile(temp, 'genres.mp3');
        final prepared = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(
              id: 'server-track-1',
              artist: 'Gorillaz',
              album: 'The Now Now',
              genres: const <String>['trip hop', 'rock'],
            ),
            filePath: mediaFile.path,
          ),
        );
        await storage.upsertDownload(prepared);

        final localTracks = await storage.readLocalDownloadedTracks();
        final groups = offlineArtistGroups(localTracks);

        expect(localTracks.single.genres, contains('trip hop'));
        expect(groups.single.toArtist().albumCount, 1);
        expect(groups.single.toArtist().genres, contains('trip hop'));
        expect(groups.single.albums.single.toAlbum().trackCount, 1);
        expect(groups.single.albums.single.toAlbum().genres, contains('rock'));
      },
    );

    test('selects missing and legacy offline metadata for repair', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_metadata_repair_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      const serverBaseUrl = 'http://server-one.test/api/v1';
      final mediaFile = await _mediaFile(temp, 'repair.mp3');
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: serverBaseUrl,
          track: _track(id: 'server-track-1'),
          filePath: mediaFile.path,
        ),
      );
      await storage.upsertDownload(prepared);

      final missing = await storage.readMetadataRepairRequests(serverBaseUrl);
      expect(
        missing.map((item) => item.serverTrackId),
        contains('server-track-1'),
      );

      await storage.upsertOfflineMetadataFragment(
        serverBaseUrl,
        'server-track-1',
        _offlineMetadata(
          trackId: 'server-track-1',
          schemaVersion: OfflineTrackMetadata.currentSchemaVersion - 1,
          albumYear: null,
          albumGenres: const <String>[],
        ),
      );

      final stale = await storage.readMetadataRepairRequests(serverBaseUrl);
      expect(
        stale.map((item) => item.serverTrackId),
        contains('server-track-1'),
      );

      await storage.upsertOfflineMetadataFragment(
        serverBaseUrl,
        'server-track-1',
        _offlineMetadata(
          trackId: 'server-track-1',
          schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
          albumYear: null,
          albumGenres: const <String>[],
          artistGenres: const <String>[],
        ),
      );

      final current = await storage.readMetadataRepairRequests(serverBaseUrl);
      expect(current, isEmpty);

      final dbPath = _join(
        _join(temp.path, 'offline'),
        'phonolite_offline.sqlite',
      );
      final db = sqlite3.open(dbPath);
      db.execute(
        '''
        UPDATE offline_metadata_fragments
        SET track_json = '{bad json'
        WHERE server_base_url = ? AND server_track_id = ?
        ''',
        [serverBaseUrl, 'server-track-1'],
      );
      db.dispose();

      final corrupt = await storage.readMetadataRepairRequests(serverBaseUrl);
      expect(
        corrupt.map((item) => item.serverTrackId),
        contains('server-track-1'),
      );
    });

    test(
      'removing one source removes only that source metadata fragment',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_metadata_remove_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final firstFile = await _mediaFile(temp, 'first.mp3');
        final secondFile = await _mediaFile(temp, 'second.mp3');
        final firstMetadata = _offlineMetadata(
          trackId: 'server-one-track',
          artistSummary: 'First server artist summary.',
        );
        final secondMetadata = _offlineMetadata(
          trackId: 'server-two-track',
          artistSummary: 'Second server artist summary.',
        );

        final first = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: firstMetadata.track,
            filePath: firstFile.path,
          ).copyWith(offlineMetadata: firstMetadata),
        );
        await storage.upsertDownload(first);
        final second = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-two.test/api/v1',
            track: secondMetadata.track,
            filePath: secondFile.path,
          ).copyWith(offlineMetadata: secondMetadata),
        );
        await storage.upsertDownload(second);

        await storage.removeDownloads(<OfflineTrackDownload>[first]);

        final downloads = await storage.readDownloads();
        final localTracks = await storage.readLocalDownloadedTracks();

        expect(downloads, hasLength(1));
        expect(downloads.single.serverBaseUrl, 'http://server-two.test/api/v1');
        expect(
          downloads.single.offlineMetadata?.artist.summary,
          'Second server artist summary.',
        );
        expect(
          localTracks.single.offlineArtist?.summary,
          'Second server artist summary.',
        );
      },
    );

    test('scoped album removal prunes only unused album artwork', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_album_delete_scope_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final albumOneArt = await storage.albumArtFile(
        albumId: 'album-one',
        extension: 'png',
      );
      final albumTwoArt = await storage.albumArtFile(
        albumId: 'album-two',
        extension: 'png',
      );
      final artistLogo = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'logo',
        extension: 'png',
      );
      final artistBanner = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'banner',
        extension: 'png',
      );
      for (final file in [albumOneArt, albumTwoArt, artistLogo, artistBanner]) {
        await file.writeAsBytes(<int>[1, 2, 3]);
      }
      final firstMetadata = _offlineMetadata(
        trackId: 'track-one',
        albumId: 'album-one',
        albumTitle: 'Album One',
        albumArtPath: albumOneArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final secondMetadata = _offlineMetadata(
        trackId: 'track-two',
        albumId: 'album-two',
        albumTitle: 'Album Two',
        albumArtPath: albumTwoArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final first = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: firstMetadata.track,
          filePath: (await _mediaFile(temp, 'one.mp3')).path,
        ).copyWith(offlineMetadata: firstMetadata),
      );
      final second = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: secondMetadata.track,
          filePath: (await _mediaFile(temp, 'two.mp3')).path,
        ).copyWith(offlineMetadata: secondMetadata),
      );
      await storage.upsertDownloads([first, second]);

      final result = await storage.removeDownloadsScoped(
        OfflineDeletionRequest(
          scope: const OfflineDeletionScope.album(
            id: 'album-one',
            label: 'Album One',
          ),
          downloads: <OfflineTrackDownload>[first],
        ),
      );

      final pendingDeletes = await storage.readPendingFileDeletes();
      final downloads = await storage.readDownloads();
      expect(result.removedSourceCount, 1);
      expect(result.removedLocalTrackCount, 1);
      expect(downloads, hasLength(1));
      expect(downloads.single.track.albumId, 'album-two');
      expect(pendingDeletes, contains(albumOneArt.path));
      expect(pendingDeletes, isNot(contains(albumTwoArt.path)));
      expect(pendingDeletes, isNot(contains(artistLogo.path)));
      expect(pendingDeletes, isNot(contains(artistBanner.path)));
    });

    test('scoped artist removal prunes artist and album artwork', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_artist_delete_scope_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final albumArt = await storage.albumArtFile(
        albumId: 'album-one',
        extension: 'png',
      );
      final artistLogo = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'logo',
        extension: 'png',
      );
      final artistBanner = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'banner',
        extension: 'png',
      );
      for (final file in [albumArt, artistLogo, artistBanner]) {
        await file.writeAsBytes(<int>[1, 2, 3]);
      }
      final metadata = _offlineMetadata(
        trackId: 'track-one',
        albumId: 'album-one',
        albumArtPath: albumArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final download = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: metadata.track,
          filePath: (await _mediaFile(temp, 'one.mp3')).path,
        ).copyWith(offlineMetadata: metadata),
      );
      await storage.upsertDownload(download);

      await storage.removeDownloadsScoped(
        OfflineDeletionRequest(
          scope: const OfflineDeletionScope.artist(
            id: 'artist-1',
            label: 'The Artist',
          ),
          downloads: <OfflineTrackDownload>[download],
        ),
      );

      final pendingDeletes = await storage.readPendingFileDeletes();
      expect(await storage.readDownloads(), isEmpty);
      expect(await storage.readLocalDownloadedTracks(), isEmpty);
      expect(
        pendingDeletes,
        containsAll([albumArt.path, artistLogo.path, artistBanner.path]),
      );
    });

    test(
      'startup garbage collection prunes old orphan tracks and art',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_startup_gc_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final albumArt = await storage.albumArtFile(
          albumId: 'album-one',
          extension: 'png',
        );
        await albumArt.writeAsBytes(<int>[1, 2, 3]);
        final metadata = _offlineMetadata(
          trackId: 'track-one',
          albumId: 'album-one',
          albumArtPath: albumArt.path,
        );
        final download = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: metadata.track,
            filePath: (await _mediaFile(temp, 'one.mp3')).path,
          ).copyWith(offlineMetadata: metadata),
        );
        await storage.upsertDownload(download);

        final dbPath = _join(
          _join(temp.path, 'offline'),
          'phonolite_offline.sqlite',
        );
        final db = sqlite3.open(dbPath);
        db.execute('DELETE FROM source_tracks');
        db.execute('DELETE FROM metadata WHERE key = ?', ['orphan_gc_v7']);
        db.execute(
          'INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)',
          ['schema_version', '6'],
        );
        db.dispose();

        expect(await storage.readLocalDownloadedTracks(), isEmpty);
        expect(await storage.readDownloads(), isEmpty);
        expect(await storage.readPendingFileDeletes(), contains(albumArt.path));
      },
    );

    test('manager waits for initial load before queueing a batch', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_queue_load_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final delegate = OfflineLibraryStorage(baseDirectory: temp);
      final storage = _DelayedReadStorage(delegate);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);

      final loadFuture = manager.load();
      var queued = false;
      final queueFuture = manager
          .queueBatch(
            _downloadManifest(batchId: 'batch-load', trackId: 'server-track-1'),
            label: 'Load Race',
          )
          .then((count) {
            queued = true;
            return count;
          });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(queued, isFalse);

      storage.releaseRead();
      expect(await queueFuture, 1);
      await loadFuture;

      final downloads = await delegate.readDownloads();
      expect(downloads.single.track.id, 'server-track-1');
      expect(downloads.single.status, OfflineDownloadStatus.queued);
      expect(downloads.single.offlineMetadata?.album.title, 'The Album');
    });

    test('large batch jobs materialize a rolling window', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_rolling_batch_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      final queued = await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-rolling',
          trackId: 'server-track-1',
          itemCount: 25,
        ),
        label: 'Large Album',
      );

      expect(queued, 25);
      expect(manager.jobs.single.jobId, 'batch-rolling');
      expect(manager.jobs.single.discoveredCount, 25);
      expect(manager.downloads, hasLength(20));
      expect(
        manager.downloads.first.offlineMetadata?.artist.name,
        'The Artist',
      );
      expect(await storage.readDownloads(), hasLength(20));

      await manager.removeDownload(manager.downloads.first);
      await _waitFor(() async {
        final downloads = manager.downloads;
        return downloads.length == 20 &&
            downloads.any((item) => item.track.id == 'server-track-21');
      });
      final topUp = manager.downloads.singleWhere(
        (item) => item.track.id == 'server-track-21',
      );
      expect(topUp.offlineMetadata?.album.title, 'The Album');
    });

    test('rolling jobs resume top-up after manager restart', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_rolling_restart_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final firstManager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      await firstManager.load();
      await firstManager.queueBatch(
        _downloadManifest(
          batchId: 'batch-restart',
          trackId: 'server-track-1',
          itemCount: 25,
        ),
        label: 'Restart Album',
      );
      expect(firstManager.downloads, hasLength(20));
      await firstManager.dispose();

      final secondManager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(secondManager.dispose);
      await secondManager.load();

      expect(secondManager.jobs.single.jobId, 'batch-restart');
      expect(secondManager.downloads, hasLength(20));

      await secondManager.removeDownload(secondManager.downloads.first);
      await _waitFor(() async {
        final downloads = secondManager.downloads;
        return downloads.length == 20 &&
            downloads.any((item) => item.track.id == 'server-track-21');
      });
    });

    test(
      'canceling a rolling job removes materialized queued downloads',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_cancel_rolling_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final manager = OfflineDownloadManager(
          connection: ServerConnection(
            baseUrl: 'http://server-one.test/api/v1',
          ),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        await manager.queueBatch(
          _downloadManifest(
            batchId: 'batch-cancel',
            trackId: 'server-track-1',
            itemCount: 25,
          ),
          label: 'Cancel Album',
        );
        expect(manager.downloads, hasLength(20));

        await manager.cancelDownloadJob(manager.jobs.single);

        expect(manager.jobs, isEmpty);
        expect(manager.downloads, isEmpty);
        expect(await storage.readDownloads(), isEmpty);
        final items = await storage.readDownloadJobItems('batch-cancel');
        expect(items, isEmpty);
      },
    );

    test('rolling jobs dedupe repeated collection requests', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_dedupe_rolling_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      final firstQueued = await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-dedupe',
          trackId: 'server-track-1',
          itemCount: 25,
        ),
        label: 'Dedupe Album',
      );
      final secondQueued = await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-dedupe',
          trackId: 'server-track-1',
          itemCount: 25,
        ),
        label: 'Dedupe Album',
      );

      expect(firstQueued, 25);
      expect(secondQueued, 0);
      expect(manager.jobs, hasLength(1));
      expect(manager.downloads, hasLength(20));
    });

    test('offline manager keeps one active download per server', () {
      expect(OfflineDownloadManager.maxParallelDownloadsPerServer, 1);
    });

    test('rolling job scheduler alternates runnable job groups', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_round_robin_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final requested = <String>[];
      final firstRequest = Completer<void>();
      final releaseFirst = Completer<void>();
      final fourthRequest = Completer<void>();
      addTearDown(() {
        if (!releaseFirst.isCompleted) {
          releaseFirst.complete();
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (!request.uri.pathSegments.contains('tracks')) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final trackId = request.uri.pathSegments.last;
        requested.add(trackId);
        if (!firstRequest.isCompleted) {
          firstRequest.complete();
          await releaseFirst.future;
        }
        if (requested.length >= 4 && !fourthRequest.isCompleted) {
          fourthRequest.complete();
        }
        try {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = 3;
          request.response.add(<int>[1, 2, 3]);
          await request.response.close();
        } catch (_) {}
      });
      addTearDown(subscription.cancel);
      addTearDown(server.close);
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final connection = ServerConnection(
        baseUrl: 'http://${server.address.address}:${server.port}/api/v1',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-a',
          trackId: 'a-track-1',
          itemCount: 25,
          trackPrefix: 'a-track-',
        ),
        label: 'A',
      );
      await firstRequest.future.timeout(const Duration(seconds: 3));
      await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-b',
          trackId: 'b-track-1',
          itemCount: 25,
          trackPrefix: 'b-track-',
        ),
        label: 'B',
      );

      releaseFirst.complete();
      await fourthRequest.future.timeout(const Duration(seconds: 5));

      expect(requested.take(4), <String>[
        'a-track-1',
        'b-track-1',
        'a-track-2',
        'b-track-2',
      ]);
    });

    test(
      'paused rolling job leaves queued rows blocked while another job runs',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_paused_job_blocks_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final requested = <String>[];
        final firstRequest = Completer<void>();
        final secondRequest = Completer<void>();
        final releaseFirst = Completer<void>();
        addTearDown(() {
          if (!releaseFirst.isCompleted) {
            releaseFirst.complete();
          }
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (!request.uri.pathSegments.contains('tracks')) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          final trackId = request.uri.pathSegments.last;
          requested.add(trackId);
          if (!firstRequest.isCompleted) {
            firstRequest.complete();
            await releaseFirst.future;
          } else if (!secondRequest.isCompleted) {
            secondRequest.complete();
          }
          try {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 3;
            request.response.add(<int>[1, 2, 3]);
            await request.response.close();
          } catch (_) {}
        });
        addTearDown(subscription.cancel);
        addTearDown(server.close);
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final connection = ServerConnection(
          baseUrl: 'http://${server.address.address}:${server.port}/api/v1',
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        await manager.queueBatch(
          _downloadManifest(
            batchId: 'batch-paused',
            trackId: 'paused-track-1',
            itemCount: 25,
            trackPrefix: 'paused-track-',
          ),
          label: 'Paused',
        );
        await firstRequest.future.timeout(const Duration(seconds: 3));
        await manager.queueBatch(
          _downloadManifest(
            batchId: 'batch-next',
            trackId: 'next-track-1',
            itemCount: 25,
            trackPrefix: 'next-track-',
          ),
          label: 'Next',
        );

        await manager.pauseDownloadJob(
          manager.jobs.singleWhere((job) => job.jobId == 'batch-paused'),
        );
        releaseFirst.complete();
        await secondRequest.future.timeout(const Duration(seconds: 5));

        final pausedJob = manager.jobs.singleWhere(
          (job) => job.jobId == 'batch-paused',
        );
        final pausedJobDownloads = manager.downloads
            .where((download) => download.batchId == pausedJob.jobId)
            .toList(growable: false);
        expect(pausedJob.status, OfflineDownloadStatus.paused);
        expect(requested.take(2), <String>['paused-track-1', 'next-track-1']);
        expect(
          pausedJobDownloads
              .where(
                (download) => download.status == OfflineDownloadStatus.queued,
              )
              .length,
          greaterThan(0),
        );
        expect(
          pausedJobDownloads
              .where(
                (download) => download.status == OfflineDownloadStatus.paused,
              )
              .length,
          1,
        );
      },
    );

    test('artist rolling jobs dedupe repeated artist requests', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_dedupe_artist_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      final artist = Artist(id: 'artist-1', name: 'Gorillaz', albumCount: 2);
      final albums = <Album>[
        Album(
          id: 'album-1',
          title: 'Demon Days',
          artist: 'Gorillaz',
          artistId: artist.id,
          trackCount: 15,
        ),
        Album(
          id: 'album-2',
          title: 'Plastic Beach',
          artist: 'Gorillaz',
          artistId: artist.id,
          trackCount: 16,
        ),
      ];

      final firstQueued = await manager.queueArtist(artist, albums);
      final secondQueued = await manager.queueArtist(artist, albums);

      expect(firstQueued, 31);
      expect(secondQueued, 0);
      expect(manager.jobs, hasLength(1));
      expect(manager.jobs.single.kind, 'artist');
      expect(manager.jobs.single.sourceId, artist.id);
      expect((await storage.readDownloadJobs()).single.sourceId, artist.id);
    });

    test(
      'artist job pause and resume requeues materialized downloads',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_artist_pause_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final jobId = 'job-artist-pause';
        final now = DateTime.fromMillisecondsSinceEpoch(10);
        final firstTrack = _track(id: 'server-track-1');
        final secondTrack = _track(id: 'server-track-2', title: 'Second Song');
        await storage.upsertDownloadJob(
          OfflineDownloadJob(
            jobId: jobId,
            kind: 'artist',
            serverBaseUrl: serverBaseUrl,
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            totalCount: 2,
            discoveredCount: 2,
            materializedCount: 2,
            label: 'Gorillaz',
          ),
        );
        await storage.upsertDownloadJobItems([
          OfflineDownloadJobItem(
            jobId: jobId,
            position: 0,
            serverTrackId: firstTrack.id,
            status: OfflineDownloadStatus.queued,
            materialized: true,
            createdAt: now,
            updatedAt: now,
            track: firstTrack,
          ),
          OfflineDownloadJobItem(
            jobId: jobId,
            position: 1,
            serverTrackId: secondTrack.id,
            status: OfflineDownloadStatus.queued,
            materialized: true,
            createdAt: now,
            updatedAt: now,
            track: secondTrack,
          ),
        ]);
        final downloads = await storage.prepareDownloads([
          _download(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: firstTrack,
            status: OfflineDownloadStatus.queued,
          ),
          _download(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: secondTrack,
            status: OfflineDownloadStatus.queued,
          ),
        ]);
        await storage.upsertDownloads(downloads);

        final manager = OfflineDownloadManager(
          connection: ServerConnection(baseUrl: serverBaseUrl),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        await manager.pauseDownloadJob(manager.jobs.single);

        expect(manager.jobs.single.status, OfflineDownloadStatus.paused);
        expect(
          manager.downloads.map((download) => download.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );
        expect(
          (await storage.readDownloadJobItems(
            jobId,
          )).map((item) => item.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );

        await manager.resumeDownloadJob(manager.jobs.single);

        expect(manager.jobs.single.status, OfflineDownloadStatus.queued);
        expect(
          manager.downloads.map((download) => download.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );
        expect(
          (await storage.readDownloadJobItems(
            jobId,
          )).map((item) => item.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );
      },
    );

    test('server bulk pause freezes queued rolling jobs and tracks', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_server_pause_all_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final serverBaseUrl = 'http://server-one.test/api/v1';
      final jobId = 'job-server-pause-all';
      final now = DateTime.fromMillisecondsSinceEpoch(10);
      final firstTrack = _track(id: 'server-track-1');
      final secondTrack = _track(id: 'server-track-2', title: 'Second Song');
      await storage.upsertDownloadJob(
        OfflineDownloadJob(
          jobId: jobId,
          kind: 'artist',
          serverBaseUrl: serverBaseUrl,
          status: OfflineDownloadStatus.queued,
          createdAt: now,
          updatedAt: now,
          totalCount: 2,
          discoveredCount: 2,
          materializedCount: 2,
          label: 'Gorillaz',
        ),
      );
      await storage.upsertDownloadJobItems([
        OfflineDownloadJobItem(
          jobId: jobId,
          position: 0,
          serverTrackId: firstTrack.id,
          status: OfflineDownloadStatus.queued,
          materialized: true,
          createdAt: now,
          updatedAt: now,
          track: firstTrack,
        ),
        OfflineDownloadJobItem(
          jobId: jobId,
          position: 1,
          serverTrackId: secondTrack.id,
          status: OfflineDownloadStatus.queued,
          materialized: true,
          createdAt: now,
          updatedAt: now,
          track: secondTrack,
        ),
      ]);
      final downloads = await storage.prepareDownloads([
        _download(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: firstTrack,
          status: OfflineDownloadStatus.queued,
        ),
        _download(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: secondTrack,
          status: OfflineDownloadStatus.queued,
        ),
      ]);
      await storage.upsertDownloads(downloads);

      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      await manager.pauseDownloadsForServer(serverBaseUrl);

      expect(manager.jobs.single.status, OfflineDownloadStatus.paused);
      expect(
        manager.downloads.map((download) => download.status).toSet(),
        <OfflineDownloadStatus>{OfflineDownloadStatus.paused},
      );
      expect(
        (await storage.readDownloadJobItems(
          jobId,
        )).map((item) => item.status).toSet(),
        <OfflineDownloadStatus>{OfflineDownloadStatus.paused},
      );
    });

    test('re-queueing a paused artist job starts a fresh queued job', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_artist_requeue_paused_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final serverBaseUrl = 'http://server-one.test/api/v1';
      final now = DateTime.fromMillisecondsSinceEpoch(10);
      final artist = Artist(id: 'artist-1', name: 'Gorillaz', albumCount: 2);
      final albums = <Album>[
        Album(
          id: 'album-1',
          title: 'Demon Days',
          artist: 'Gorillaz',
          artistId: artist.id,
          trackCount: 15,
        ),
        Album(
          id: 'album-2',
          title: 'Plastic Beach',
          artist: 'Gorillaz',
          artistId: artist.id,
          trackCount: 16,
        ),
      ];
      await storage.upsertDownloadJob(
        OfflineDownloadJob(
          jobId: 'stale-paused-artist',
          kind: 'artist',
          serverBaseUrl: serverBaseUrl,
          status: OfflineDownloadStatus.paused,
          createdAt: now,
          updatedAt: now,
          totalCount: 31,
          label: artist.name,
        ),
      );
      await storage.upsertDownloadJobSources([
        for (var index = 0; index < albums.length; index += 1)
          OfflineDownloadJobSource(
            jobId: 'stale-paused-artist',
            position: index,
            sourceId: albums[index].id,
            status: OfflineDownloadStatus.queued,
            createdAt: now,
            updatedAt: now,
            label: albums[index].title,
          ),
      ]);

      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      final queued = await manager.queueArtist(artist, albums);

      expect(queued, 31);
      expect(manager.jobs, hasLength(1));
      expect(manager.jobs.single.status, OfflineDownloadStatus.queued);
      expect(manager.jobs.single.jobId, isNot('stale-paused-artist'));
      expect(
        await storage.readDownloadJobItems('stale-paused-artist'),
        isEmpty,
      );
    });

    test(
      'resuming a paused artist track resumes the parent artist job',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_artist_track_resume_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final jobId = 'job-artist-track-resume';
        final now = DateTime.fromMillisecondsSinceEpoch(10);
        final firstTrack = _track(id: 'server-track-1');
        final secondTrack = _track(id: 'server-track-2', title: 'Second Song');
        await storage.upsertDownloadJob(
          OfflineDownloadJob(
            jobId: jobId,
            kind: 'artist',
            serverBaseUrl: serverBaseUrl,
            status: OfflineDownloadStatus.paused,
            createdAt: now,
            updatedAt: now,
            totalCount: 2,
            discoveredCount: 2,
            materializedCount: 2,
            label: 'Gorillaz',
          ),
        );
        await storage.upsertDownloadJobItems([
          OfflineDownloadJobItem(
            jobId: jobId,
            position: 0,
            serverTrackId: firstTrack.id,
            status: OfflineDownloadStatus.paused,
            materialized: true,
            createdAt: now,
            updatedAt: now,
            track: firstTrack,
          ),
          OfflineDownloadJobItem(
            jobId: jobId,
            position: 1,
            serverTrackId: secondTrack.id,
            status: OfflineDownloadStatus.paused,
            materialized: true,
            createdAt: now,
            updatedAt: now,
            track: secondTrack,
          ),
        ]);
        final downloads = await storage.prepareDownloads([
          _download(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: firstTrack,
            status: OfflineDownloadStatus.paused,
          ),
          _download(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: secondTrack,
            status: OfflineDownloadStatus.paused,
          ),
        ]);
        await storage.upsertDownloads(downloads);

        final manager = OfflineDownloadManager(
          connection: ServerConnection(baseUrl: serverBaseUrl),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        await manager.resumeDownload(manager.downloads.first);

        expect(manager.jobs.single.status, OfflineDownloadStatus.queued);
        expect(
          manager.downloads.map((download) => download.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );
        expect(
          (await storage.readDownloadJobItems(
            jobId,
          )).map((item) => item.status).toSet(),
          <OfflineDownloadStatus>{OfflineDownloadStatus.queued},
        );
      },
    );

    test('completed rolling jobs prune and stay gone after removals', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_remove_completed_job_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final serverBaseUrl = 'http://server-one.test/api/v1';
      final jobId = 'job-artist-remove-completed';
      final now = DateTime.fromMillisecondsSinceEpoch(10);
      final firstFile = await _mediaFile(temp, 'first.mp3');
      final secondFile = await _mediaFile(temp, 'second.mp3');
      final firstTrack = _track(id: 'server-track-1');
      final secondTrack = _track(id: 'server-track-2', title: 'Second Song');
      await storage.upsertDownloadJob(
        OfflineDownloadJob(
          jobId: jobId,
          kind: 'artist',
          serverBaseUrl: serverBaseUrl,
          status: OfflineDownloadStatus.downloaded,
          createdAt: now,
          updatedAt: now,
          totalCount: 2,
          discoveredCount: 2,
          completedCount: 2,
          materializedCount: 2,
          label: 'Gorillaz',
        ),
      );
      await storage.upsertDownloadJobItems([
        OfflineDownloadJobItem(
          jobId: jobId,
          position: 0,
          serverTrackId: firstTrack.id,
          status: OfflineDownloadStatus.downloaded,
          materialized: true,
          createdAt: now,
          updatedAt: now,
          track: firstTrack,
        ),
        OfflineDownloadJobItem(
          jobId: jobId,
          position: 1,
          serverTrackId: secondTrack.id,
          status: OfflineDownloadStatus.downloaded,
          materialized: true,
          createdAt: now,
          updatedAt: now,
          track: secondTrack,
        ),
      ]);
      final downloads = await storage.prepareDownloads([
        _download(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: firstTrack,
          filePath: firstFile.path,
        ),
        _download(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: secondTrack,
          filePath: secondFile.path,
        ),
      ]);
      await storage.upsertDownloads(downloads);

      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      await manager.load();
      expect(manager.jobs, isEmpty);
      expect(manager.downloads, hasLength(2));
      expect(await storage.readDownloadJobs(), isEmpty);

      await manager.removeDownloads(manager.downloads);
      expect(manager.jobs, isEmpty);
      expect(await storage.readDownloadJobs(), isEmpty);

      await manager.dispose();
      final restarted = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.jobs, isEmpty);
      expect(restarted.downloads, isEmpty);
    });

    test('manager downloads media on a worker isolate', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_worker_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final body = <int>[1, 2, 3, 4];
      String? authorization;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        if (request.uri.path == '/api/v1/download/tracks/server-track-1') {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = body.length;
          request.response.add(body);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final completed = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloaded,
        ),
      );

      await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-worker',
          trackId: 'server-track-1',
          byteLength: body.length,
        ),
        label: 'Worker Album',
      );

      final downloads = await completed.timeout(const Duration(seconds: 5));
      final downloaded = downloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      expect(authorization, 'Bearer token-1');
      expect(downloaded.filePath, isNotEmpty);
      expect(downloaded.bytesDownloaded, body.length);
      expect(downloaded.bytesTotal, body.length);
      expect(await File(downloaded.filePath!).readAsBytes(), body);
    });

    test(
      'manager redownloads a removed track without inheriting cancel state',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_redownload_cancel_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final body = <int>[9, 8, 7, 6];
        var downloadRequests = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (request.uri.path == '/api/v1/download/tracks/server-track-1') {
            downloadRequests += 1;
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        addTearDown(() => server.close(force: true));

        final connection = ServerConnection(
          baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        Future<OfflineTrackDownload> nextCompleted() async {
          final downloads = await manager.stream
              .firstWhere(
                (downloads) => downloads.any(
                  (download) =>
                      download.track.id == 'server-track-1' &&
                      download.status == OfflineDownloadStatus.downloaded,
                ),
              )
              .timeout(const Duration(seconds: 5));
          return downloads.singleWhere(
            (download) => download.track.id == 'server-track-1',
          );
        }

        final firstCompleted = nextCompleted();
        await manager.queueBatch(
          _downloadManifest(
            batchId: 'batch-redownload',
            trackId: 'server-track-1',
            byteLength: body.length,
          ),
          label: 'Redownload Album',
        );
        final first = await firstCompleted;

        await manager.removeDownloads([first]);
        expect(manager.downloads, isEmpty);

        final secondCompleted = nextCompleted();
        await manager.queueBatch(
          _downloadManifest(
            batchId: 'batch-redownload',
            trackId: 'server-track-1',
            byteLength: body.length,
          ),
          label: 'Redownload Album',
        );
        final second = await secondCompleted;

        expect(downloadRequests, 2);
        expect(second.status, OfflineDownloadStatus.downloaded);
        expect(second.error, isNull);
        expect(await File(second.filePath!).readAsBytes(), body);
      },
    );

    test(
      'manager single-track downloads queue through batch metadata',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_single_batch_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final body = <int>[1, 2, 3, 4];
        var sawBatchRequest = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (request.uri.path == '/api/v1/download/batches') {
            sawBatchRequest = true;
            await request.cast<List<int>>().drain<void>();
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                _downloadManifest(
                  batchId: 'single-batch',
                  trackId: 'server-track-1',
                  byteLength: body.length,
                ).toJson(),
              ),
            );
            await request.response.close();
            return;
          }
          if (request.uri.path == '/api/v1/download/tracks/server-track-1') {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        addTearDown(() => server.close(force: true));

        final connection = ServerConnection(
          baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
        )..setToken('token-1');
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();
        final completed = manager.stream.firstWhere(
          (downloads) => downloads.any(
            (download) =>
                download.track.id == 'server-track-1' &&
                download.status == OfflineDownloadStatus.downloaded,
          ),
        );

        expect(await manager.downloadTrack(_track(id: 'server-track-1')), 1);
        final downloads = await completed.timeout(const Duration(seconds: 5));
        final downloaded = downloads.singleWhere(
          (download) => download.track.id == 'server-track-1',
        );

        expect(sawBatchRequest, isTrue);
        expect(downloaded.offlineMetadata?.artist.name, 'The Artist');
        expect(downloaded.track.offlineAlbum?.title, 'The Album');
      },
    );

    test(
      'manager repairs stale metadata once when server metadata is empty',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_manager_metadata_repair_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        var metadataRequestCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          if (request.uri.path ==
              '/api/v1/library/tracks/server-track-1/offline-metadata') {
            metadataRequestCount += 1;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                _offlineMetadata(
                  trackId: 'server-track-1',
                  albumTitle: 'Gorillaz',
                  albumId: 'album-1',
                  albumYear: null,
                  albumGenres: const <String>[],
                  artistGenres: const <String>[],
                  schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
                ).toJson(),
              ),
            );
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        addTearDown(() => server.close(force: true));

        final serverBaseUrl = 'http://127.0.0.1:${server.port}/api/v1';
        final staleMetadata = _offlineMetadata(
          trackId: 'server-track-1',
          albumTitle: 'Gorillaz',
          albumId: 'album-1',
          albumYear: null,
          albumGenres: const <String>[],
          schemaVersion: OfflineTrackMetadata.currentSchemaVersion - 1,
        );
        final prepared = await storage.prepareDownload(
          _download(
            serverBaseUrl: serverBaseUrl,
            track: staleMetadata.track,
            filePath: (await _mediaFile(temp, 'repair-auth.mp3')).path,
          ).copyWith(offlineMetadata: staleMetadata),
        );
        await storage.upsertDownload(prepared);

        final connection = ServerConnection(baseUrl: serverBaseUrl);
        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();
        expect(
          manager.localDownloadedTracks().single.offlineAlbum?.year,
          isNull,
        );

        connection.setToken('token-1');
        await manager.repairOfflineMetadataFragments();
        final groups = offlineArtistGroups(manager.localDownloadedTracks());

        expect(metadataRequestCount, 1);
        expect(groups.single.albums.single.toAlbum().year, isNull);
        expect(groups.single.albums.single.toAlbum().genres, isEmpty);

        await manager.repairOfflineMetadataFragments();
        expect(metadataRequestCount, 1);
      },
    );

    test('persists local album and artist artwork paths', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_art_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);

      final mediaFile = await _mediaFile(temp, 'completed.mp3');
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-track-1'),
          filePath: mediaFile.path,
        ),
      );
      await storage.upsertDownload(prepared);

      final albumArt = await storage.albumArtFile(
        albumId: 'album-1',
        extension: 'png',
      );
      final artistLogo = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'logo',
        extension: 'png',
      );
      final artistBanner = await storage.artistArtFile(
        artistId: 'artist-1',
        kind: 'banner',
        extension: 'png',
      );
      await albumArt.writeAsBytes(<int>[1, 2, 3]);
      await artistLogo.writeAsBytes(<int>[4, 5, 6]);
      await artistBanner.writeAsBytes(<int>[7, 8, 9]);

      await storage.updateTrackArtPaths(
        prepared.localTrackId!,
        albumArtPath: albumArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );

      final downloads = await storage.readDownloads();
      final localTracks = await storage.readLocalDownloadedTracks();

      expect(downloads.single.track.albumArtPath, albumArt.path);
      expect(downloads.single.track.artistArtPath, artistLogo.path);
      expect(downloads.single.track.artistBannerPath, artistBanner.path);
      expect(localTracks.single.albumArtPath, albumArt.path);
      expect(localTracks.single.artistArtPath, artistLogo.path);
      expect(localTracks.single.artistBannerPath, artistBanner.path);
    });

    test(
      'manager removal deletes cached files and prunes local user data',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_remove_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);

        final mediaFile = await _mediaFile(temp, 'completed.mp3');
        final partialFile = await _mediaFile(temp, 'completed.mp3.part');
        final prepared = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'server-track-1'),
            filePath: mediaFile.path,
          ).copyWith(partialPath: partialFile.path),
        );
        await storage.upsertDownload(prepared);
        final localTrackId = prepared.localTrackId!;
        final playlist = await storage.createLocalPlaylist('Local Mix');
        await storage.setLocalLike(localTrackId, true);
        await storage.addLocalTrackToPlaylist(playlist.id, localTrackId);

        final manager = OfflineDownloadManager(
          connection: ServerConnection(
            baseUrl: 'http://server-one.test/api/v1',
          ),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();
        await manager.loadLocalPlaylistTracks(playlist.id);

        expect(manager.localLiked, hasLength(1));
        expect(manager.localPlaylistTracks, hasLength(1));

        await manager.removeDownload(prepared);
        await _waitFor(
          () async => !await mediaFile.exists() && !await partialFile.exists(),
        );

        expect(await mediaFile.exists(), isFalse);
        expect(await partialFile.exists(), isFalse);
        expect(await storage.readDownloads(), isEmpty);
        expect(await storage.readLocalLikedTracks(), isEmpty);
        expect(await storage.readLocalPlaylistTracks(playlist.id), isEmpty);
        expect(manager.localLiked, isEmpty);
        expect(manager.localPlaylistTracks, isEmpty);
      },
    );

    test('manager removal tolerates already-missing files', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_remove_missing_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final missing = _join(temp.path, 'missing.mp3');
      final prepared = await storage.prepareDownload(
        _download(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: _track(id: 'server-track-1'),
          filePath: missing,
        ),
      );
      await storage.upsertDownload(prepared);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      await manager.removeDownload(prepared);

      expect(await storage.readDownloads(), isEmpty);
    });

    test(
      'bulk storage removal prunes metadata and records file cleanup',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_bulk_remove_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);

        final firstFile = await _mediaFile(temp, 'first.mp3');
        final secondFile = await _mediaFile(temp, 'second.mp3');
        final first = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'server-track-1'),
            filePath: firstFile.path,
          ),
        );
        final second = await storage.prepareDownload(
          _download(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: _track(id: 'server-track-2', title: 'Second Song'),
            filePath: secondFile.path,
          ),
        );
        await storage.upsertDownloads([first, second]);
        final playlist = await storage.createLocalPlaylist('Local Mix');
        await storage.setLocalLike(first.localTrackId!, true);
        await storage.setLocalLike(second.localTrackId!, true);
        await storage.addLocalTrackToPlaylist(playlist.id, first.localTrackId!);
        await storage.addLocalTrackToPlaylist(
          playlist.id,
          second.localTrackId!,
        );

        await storage.removeDownloads([first, second, first]);

        final pendingDeletes = await storage.readPendingFileDeletes();
        expect(await storage.readDownloads(), isEmpty);
        expect(await storage.readLocalLikedTracks(), isEmpty);
        expect(await storage.readLocalPlaylistTracks(playlist.id), isEmpty);
        expect(pendingDeletes, containsAll([firstFile.path, secondFile.path]));
        expect(await firstFile.exists(), isTrue);
        expect(await secondFile.exists(), isTrue);
      },
    );

    test('manager resumes pending file cleanup on load', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_pending_cleanup_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final mediaFile = await _mediaFile(temp, 'pending.mp3');
      final missingFile = File(_join(temp.path, 'already-gone.mp3'));
      await storage.recordPendingFileDeletes([
        mediaFile.path,
        missingFile.path,
      ]);

      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      await _waitFor(
        () async =>
            !await mediaFile.exists() &&
            (await storage.readPendingFileDeletes()).isEmpty,
      );
      expect(await mediaFile.exists(), isFalse);
      expect(await storage.readPendingFileDeletes(), isEmpty);
    });

    test('active removal does not resurrect canceled worker state', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_remove_active_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final firstChunkSent = Completer<void>();
      final releaseResponse = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        try {
          if (request.uri.path == '/api/v1/download/tracks/server-track-1') {
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 6;
            request.response.add(<int>[1, 2, 3]);
            await request.response.flush();
            if (!firstChunkSent.isCompleted) {
              firstChunkSent.complete();
            }
            await releaseResponse.future;
            request.response.add(<int>[4, 5, 6]);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } catch (_) {
          if (!firstChunkSent.isCompleted) {
            firstChunkSent.complete();
          }
        }
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final downloading = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloading,
        ),
      );

      await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-active-remove',
          trackId: 'server-track-1',
          byteLength: 6,
        ),
        label: 'Active Remove',
      );

      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      final activeDownloads = await downloading.timeout(
        const Duration(seconds: 5),
      );
      final active = activeDownloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      await manager.removeDownload(active);
      releaseResponse.complete();

      await _waitFor(() async => (await storage.readDownloads()).isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(manager.downloads, isEmpty);
      expect(await storage.readDownloads(), isEmpty);
    });

    test('fast resume is not overwritten by active pause cleanup', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_resume_active_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final firstChunkSent = Completer<void>();
      final releaseFirstResponse = Completer<void>();
      var requestCount = 0;
      addTearDown(() {
        if (!releaseFirstResponse.isCompleted) {
          releaseFirstResponse.complete();
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        try {
          if (request.uri.path == '/api/v1/download/tracks/server-track-1') {
            requestCount += 1;
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 6;
            if (requestCount == 1) {
              request.response.add(<int>[1, 2, 3]);
              await request.response.flush();
              if (!firstChunkSent.isCompleted) {
                firstChunkSent.complete();
              }
              await releaseFirstResponse.future;
              request.response.add(<int>[4, 5, 6]);
              await request.response.close();
              return;
            }
            request.response.add(<int>[1, 2, 3, 4, 5, 6]);
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        } catch (_) {
          if (!firstChunkSent.isCompleted) {
            firstChunkSent.complete();
          }
        }
      });
      addTearDown(subscription.cancel);
      addTearDown(() => server.close(force: true));

      final connection = ServerConnection(
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
      )..setToken('token-1');
      final manager = OfflineDownloadManager(
        connection: connection,
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();
      final downloading = manager.stream.firstWhere(
        (downloads) => downloads.any(
          (download) =>
              download.track.id == 'server-track-1' &&
              download.status == OfflineDownloadStatus.downloading,
        ),
      );

      await manager.queueBatch(
        _downloadManifest(
          batchId: 'batch-active-resume',
          trackId: 'server-track-1',
          byteLength: 6,
        ),
        label: 'Active Resume',
      );

      await firstChunkSent.future.timeout(const Duration(seconds: 5));
      final activeDownloads = await downloading.timeout(
        const Duration(seconds: 5),
      );
      final active = activeDownloads.singleWhere(
        (download) => download.track.id == 'server-track-1',
      );

      await manager.pauseDownload(active);
      await manager.resumeDownload(manager.downloads.single);
      releaseFirstResponse.complete();

      await _waitFor(
        () async =>
            manager.downloads.single.status == OfflineDownloadStatus.downloaded,
      );
      expect(requestCount, greaterThanOrEqualTo(2));
    });
  });
}

Track _track({
  required String id,
  String title = 'The Song',
  String artist = 'The Artist',
  String artistId = 'artist-1',
  String album = 'The Album',
  String albumId = 'album-1',
  String? albumArtPath,
  String? artistArtPath,
  String? artistBannerPath,
  List<String> genres = const <String>[],
  int durationMs = 180000,
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    artistId: artistId,
    album: album,
    albumId: albumId,
    albumArtPath: albumArtPath,
    artistArtPath: artistArtPath,
    artistBannerPath: artistBannerPath,
    genres: genres,
    durationMs: durationMs,
    liked: false,
    inPlaylists: false,
    trackNo: 1,
    discNo: 1,
  );
}

OfflineTrackDownload _download({
  required String serverBaseUrl,
  required Track track,
  String? batchId,
  OfflineDownloadStatus status = OfflineDownloadStatus.downloaded,
  String? filePath,
}) {
  return OfflineTrackDownload(
    serverBaseUrl: serverBaseUrl,
    batchId: batchId,
    track: track,
    status: status,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    filePath: filePath,
    bytesDownloaded: filePath == null ? 0 : 3,
    bytesTotal: filePath == null ? null : 3,
  );
}

DownloadBatchManifest _downloadManifest({
  required String batchId,
  required String trackId,
  int byteLength = 1,
  int itemCount = 1,
  String trackPrefix = 'server-track-',
}) {
  final ids = itemCount <= 1
      ? <String>[trackId]
      : List<String>.generate(itemCount, (index) => '$trackPrefix${index + 1}');
  return DownloadBatchManifest(
    schemaVersion: 1,
    batchId: batchId,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    items: [
      for (final id in ids)
        DownloadBatchItem(
          trackId: id,
          downloadUrl: '/api/v1/download/tracks/$id',
          offlineMetadata: OfflineTrackMetadata(
            schemaVersion: 1,
            track: _track(id: id),
            album: Album(
              id: 'album-1',
              title: 'The Album',
              artist: 'The Artist',
              artistId: 'artist-1',
              trackCount: ids.length,
            ),
            artist: Artist(id: 'artist-1', name: 'The Artist', albumCount: 1),
          ),
          byteLength: byteLength,
          contentType: 'audio/mpeg',
          etag: '"$id"',
          sha256: '',
        ),
    ],
    unavailable: const [],
  );
}

extension _DownloadBatchManifestTestJson on DownloadBatchManifest {
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'batch_id': batchId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'items': [
      for (final item in items)
        {
          'track_id': item.trackId,
          'download_url': item.downloadUrl,
          'offline_metadata': item.offlineMetadata.toJson(),
          'byte_length': item.byteLength,
          'content_type': item.contentType,
          'etag': item.etag,
          'sha256': item.sha256,
        },
    ],
    'unavailable': [
      for (final item in unavailable)
        {'track_id': item.trackId, 'reason': item.reason},
    ],
  };
}

OfflineTrackMetadata _offlineMetadata({
  required String trackId,
  int schemaVersion = 1,
  String trackTitle = 'The Song',
  String albumTitle = 'The Album',
  String albumId = 'album-1',
  String albumSummary = 'Stored album summary.',
  String artistName = 'The Artist',
  String artistId = 'artist-1',
  String artistSummary = 'Stored artist summary.',
  String? albumArtPath,
  String? artistArtPath,
  String? artistBannerPath,
  int? albumYear = 1998,
  List<String> albumGenres = const <String>['trip hop', 'downtempo'],
  List<String> artistGenres = const <String>['trip hop'],
}) {
  return OfflineTrackMetadata(
    schemaVersion: schemaVersion,
    track: _track(
      id: trackId,
      title: trackTitle,
      artist: artistName,
      artistId: artistId,
      album: albumTitle,
      albumId: albumId,
      albumArtPath: albumArtPath,
      artistArtPath: artistArtPath,
      artistBannerPath: artistBannerPath,
    ),
    album: Album(
      id: albumId,
      title: albumTitle,
      artist: artistName,
      artistId: artistId,
      trackCount: 12,
      year: albumYear,
      genres: albumGenres,
      summary: albumSummary,
    ),
    artist: Artist(
      id: artistId,
      name: artistName,
      albumCount: 4,
      genres: artistGenres,
      summary: artistSummary,
      logoRef: 'artists/artist-1/logo.png',
      bannerRef: 'artists/artist-1/banner.png',
    ),
  );
}

class _DelayedReadStorage extends OfflineLibraryStorage {
  _DelayedReadStorage(this.delegate);

  final OfflineLibraryStorage delegate;
  final Completer<void> _readCompleter = Completer<void>();

  void releaseRead() {
    if (!_readCompleter.isCompleted) {
      _readCompleter.complete();
    }
  }

  @override
  Future<List<OfflineTrackDownload>> readDownloads() async {
    await _readCompleter.future;
    return delegate.readDownloads();
  }

  @override
  Future<List<OfflineDownloadBatch>> readDownloadBatches() {
    return delegate.readDownloadBatches();
  }

  @override
  Future<List<Playlist>> readLocalPlaylists() {
    return delegate.readLocalPlaylists();
  }

  @override
  Future<List<Track>> readLocalLikedTracks() {
    return delegate.readLocalLikedTracks();
  }

  @override
  Future<List<Track>> readLocalPlaylistTracks(String playlistId) {
    return delegate.readLocalPlaylistTracks(playlistId);
  }

  @override
  Future<List<OfflineTrackDownload>> prepareDownloads(
    List<OfflineTrackDownload> downloads,
  ) {
    return delegate.prepareDownloads(downloads);
  }

  @override
  Future<void> upsertDownloads(List<OfflineTrackDownload> downloads) {
    return delegate.upsertDownloads(downloads);
  }

  @override
  Future<void> removeDownloads(Iterable<OfflineTrackDownload> downloads) {
    return delegate.removeDownloads(downloads);
  }

  @override
  Future<OfflineDeletionResult> removeDownloadsScoped(
    OfflineDeletionRequest request,
  ) {
    return delegate.removeDownloadsScoped(request);
  }

  @override
  Future<void> recordPendingFileDeletes(Iterable<String?> paths) {
    return delegate.recordPendingFileDeletes(paths);
  }

  @override
  Future<List<String>> readPendingFileDeletes() {
    return delegate.readPendingFileDeletes();
  }

  @override
  Future<void> clearPendingFileDeletes(Iterable<String> paths) {
    return delegate.clearPendingFileDeletes(paths);
  }

  @override
  Future<bool> isManagedDeletePath(String path) {
    return delegate.isManagedDeletePath(path);
  }

  @override
  Future<void> upsertDownloadBatch(OfflineDownloadBatch batch) {
    return delegate.upsertDownloadBatch(batch);
  }
}

Future<File> _mediaFile(Directory temp, String name) async {
  final dir = Directory(_join(_join(temp.path, 'offline'), 'test_media'));
  await dir.create(recursive: true);
  final file = File(_join(dir.path, name));
  await file.writeAsBytes(<int>[1, 2, 3]);
  return file;
}

String _join(String left, String right) {
  final separator = Platform.pathSeparator;
  if (left.endsWith(separator)) {
    return '$left$right';
  }
  return '$left$separator$right';
}

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (!await condition()) {
    throw TimeoutException('condition was not met before $timeout');
  }
}
