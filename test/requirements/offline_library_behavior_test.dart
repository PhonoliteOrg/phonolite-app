import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_metadata.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/storage/preferences/offline_storage_settings_storage.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('offline library sqlite behavior', () {
    test('migrates legacy JSON downloads into sqlite on first read', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_json_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final root = Directory(offlineTestJoin(temp.path, 'offline'));
      await root.create(recursive: true);
      final mediaFile = File(offlineTestJoin(root.path, 'track.mp3'));
      await mediaFile.writeAsBytes(<int>[1, 2, 3]);

      final legacy = OfflineTrackDownload(
        serverBaseUrl: 'http://server-one.test/api/v1',
        track: offlineTestTrack(id: 'server-track-1'),
        status: OfflineDownloadStatus.downloaded,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
        filePath: mediaFile.path,
        bytesDownloaded: 3,
        bytesTotal: 3,
      );
      await File(
        offlineTestJoin(root.path, 'offline_library.json'),
      ).writeAsString(
        jsonEncode({
          'downloads': [legacy.toJson()],
        }),
      );

      final downloads = await storage.readDownloads();

      expect(downloads, hasLength(1));
      expect(downloads.single.track.id, 'server-track-1');
      expect(downloads.single.localTrackId, startsWith('lt_'));
      expect(
        await File(
          offlineTestJoin(root.path, 'phonolite_offline.sqlite'),
        ).exists(),
        isTrue,
      );
    });

    test('merges matching metadata from different server sources', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_merge_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);

      final fileOne = await offlineTestMediaFile(temp, 'one.mp3');
      final first = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(id: 'server-one-track', durationMs: 180000),
          filePath: fileOne.path,
        ),
      );
      await storage.upsertDownload(first);

      final fileTwo = await offlineTestMediaFile(temp, 'two.mp3');
      final second = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-two.test/api/v1',
          track: offlineTestTrack(
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
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'queued-track'),
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

        final mediaFile = await offlineTestMediaFile(temp, 'completed.mp3');
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

    for (final relocate in [false, true]) {
      test(
        'restores playlist covers after ${relocate ? 'container relocation' : 'upgrading legacy path repair'}',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'phonolite_playlist_restart_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final original = Directory(offlineTestJoin(temp.path, 'original'));
          final storage = OfflineLibraryStorage(baseDirectory: original);
          final playlist = await storage.createLocalPlaylist('Cover Mix');
          final saved = await storage.updateLocalPlaylistImage(
            playlist.id,
            PlaylistImageEdit.replace(
              bytes: Uint8List.fromList([1, 2, 3]),
              contentType: 'image/png',
            ),
          );
          final originalPath = saved!.imagePath!;
          await storage.close();

          final Directory current;
          if (relocate) {
            current = await original.rename(
              offlineTestJoin(temp.path, 'relocated'),
            );
          } else {
            current = original;
            final db = sqlite3.open(
              offlineTestJoin(
                offlineTestJoin(original.path, 'offline'),
                'phonolite_offline.sqlite',
              ),
            );
            // The previous version already repaired album/artist paths at this
            // location, but left a playlist reference pointing at an old container.
            db.execute('DELETE FROM metadata WHERE key = ?', [
              'playlist_artwork_repair_v1',
            ]);
            db.execute(
              'UPDATE local_playlists SET image_path = ? WHERE id = ?',
              [
                offlineTestJoin(temp.path, 'old-container/cover.png'),
                playlist.id,
              ],
            );
            db.dispose();
          }

          final restarted = OfflineLibraryStorage(baseDirectory: current);
          final restored = (await restarted.readLocalPlaylists()).single;
          final expected = await restarted.playlistArtFile(
            playlistId: playlist.id,
            extension: 'png',
          );
          expect(restored.imagePath, expected.path);
          expect(await File(restored.imagePath!).readAsBytes(), [1, 2, 3]);
          if (relocate) expect(await File(originalPath).exists(), isFalse);
          expect(
            await restarted.readPendingFileDeletes(),
            isNot(contains(expected.path)),
          );
          await restarted.close();

          final secondRestart = OfflineLibraryStorage(baseDirectory: current);
          expect(
            (await secondRestart.readLocalPlaylists()).single.imagePath,
            expected.path,
          );
          expect(await expected.exists(), isTrue);
          await secondRestart.close();
        },
      );
    }

    test('records local like and unlike history', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_like_state_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final mediaFile = await offlineTestMediaFile(temp, 'completed.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(id: 'server-track-1'),
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
      final alphaFile = await offlineTestMediaFile(temp, 'alpha.mp3');
      final zetaFile = await offlineTestMediaFile(temp, 'zeta.mp3');
      final alpha = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(
            id: 'server-alpha',
            title: 'Alpha Song',
            durationMs: 180000,
          ),
          filePath: alphaFile.path,
        ),
      );
      final zeta = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(
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

    test(
      'managed iOS storage ignores saved custom paths and clears overrides',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_ios_managed_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final settingsFiles = offlineTestSettingsFiles(
          offlineTestJoin(temp.path, 'app_support'),
        );

        final legacySettings = OfflineStorageSettingsStorage(
          files: settingsFiles,
          usesManagedStoragePaths: () => false,
        );
        await legacySettings.write(
          const OfflineStorageSettings(
            metadataDirectory: '/legacy/metadata',
            downloadsDirectory: '/legacy/downloads',
          ),
        );

        final storage = OfflineLibraryStorage(
          defaultDirectoryProvider: settingsFiles.directoryProvider,
          settingsStorage: OfflineStorageSettingsStorage(
            files: settingsFiles,
            usesManagedStoragePaths: () => true,
          ),
        );

        final locations = await storage.resolveStorageLocations();
        final expectedRoot = offlineTestJoin(
          offlineTestJoin(temp.path, 'app_support'),
          offlineTestJoin('Phonolite', 'offline'),
        );

        expect(locations.metadataDirectory, expectedRoot);
        expect(locations.downloadsDirectory, expectedRoot);
        expect(locations.metadataDirectoryIsDefault, isTrue);
        expect(locations.downloadsDirectoryIsDefault, isTrue);

        final normalized = await legacySettings.read();
        expect(normalized.metadataDirectory, isNull);
        expect(normalized.downloadsDirectory, isNull);
      },
    );

    test(
      'managed iOS storage resets update requests back to defaults',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_ios_reset_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final settingsFiles = offlineTestSettingsFiles(
          offlineTestJoin(temp.path, 'app_support'),
        );

        final storage = OfflineLibraryStorage(
          defaultDirectoryProvider: settingsFiles.directoryProvider,
          settingsStorage: OfflineStorageSettingsStorage(
            files: settingsFiles,
            usesManagedStoragePaths: () => true,
          ),
        );

        await storage.updateStorageLocations(
          metadataDirectory: '/custom/metadata',
          downloadsDirectory: '/custom/downloads',
        );

        final locations = await storage.resolveStorageLocations();
        final expectedRoot = offlineTestJoin(
          offlineTestJoin(temp.path, 'app_support'),
          offlineTestJoin('Phonolite', 'offline'),
        );

        expect(locations.metadataDirectory, expectedRoot);
        expect(locations.downloadsDirectory, expectedRoot);

        final persisted = await OfflineStorageSettingsStorage(
          files: settingsFiles,
          usesManagedStoragePaths: () => false,
        ).read();
        expect(persisted.metadataDirectory, isNull);
        expect(persisted.downloadsDirectory, isNull);
      },
    );

    test(
      'keeps metadata and download roots independently configurable',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_split_roots_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final metadataDir = Directory(offlineTestJoin(temp.path, 'metadata'));
        final downloadsDir = Directory(offlineTestJoin(temp.path, 'downloads'));
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
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-1'),
            filePath: mediaPath.path,
          ),
        );
        await storage.upsertDownload(prepared);

        expect(mediaPath.path.startsWith(downloadsDir.absolute.path), isTrue);
        expect(
          await File(
            offlineTestJoin(
              metadataDir.absolute.path,
              'phonolite_offline.sqlite',
            ),
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
        final metadataDir = Directory(offlineTestJoin(temp.path, 'metadata'));
        final downloadsDir = Directory(offlineTestJoin(temp.path, 'downloads'));
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
          offlineTestJoin(metadataDir.path, 'offline_library.json'),
        );
        await legacyIndex.writeAsString('{}');
        final walFile = File(
          offlineTestJoin(metadataDir.path, 'phonolite_offline.sqlite-wal'),
        );
        await walFile.writeAsString('');

        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-1'),
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
          offlineTestJoin(metadataDir.path, 'phonolite_offline.sqlite'),
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
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(id: 'server-track-1'),
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
      final mediaFile = await offlineTestMediaFile(temp, 'metadata.mp3');
      final metadata = offlineTestOfflineMetadata(
        trackId: 'server-track-1',
        trackTitle: 'Angel',
        albumTitle: 'Mezzanine',
        albumSummary: 'A dark, heavy album summary.',
        artistName: 'Massive Attack',
        artistSummary: 'A Bristol collective summary.',
      );

      final prepared = await storage.prepareDownload(
        offlineTestDownload(
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
          offlineTestOfflineMetadata(
            trackId: 'server-track-1',
            albumTitle: 'Cracker Island',
            albumId: 'album-2023',
            albumYear: 2023,
          ),
          offlineTestOfflineMetadata(
            trackId: 'server-track-2',
            albumTitle: 'Demon Days',
            albumId: 'album-2005',
            albumYear: 2005,
          ),
          offlineTestOfflineMetadata(
            trackId: 'server-track-3',
            albumTitle: 'A No Year Album',
            albumId: 'album-no-year',
            albumYear: null,
          ),
        ];
        for (final metadata in albums) {
          final prepared = await storage.prepareDownload(
            offlineTestDownload(
              serverBaseUrl: serverBaseUrl,
              track: metadata.track,
              filePath: (await offlineTestMediaFile(
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
        final mediaFile = await offlineTestMediaFile(temp, 'genres.mp3');
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(
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
      final mediaFile = await offlineTestMediaFile(temp, 'repair.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: serverBaseUrl,
          track: offlineTestTrack(id: 'server-track-1'),
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
        offlineTestOfflineMetadata(
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
        offlineTestOfflineMetadata(
          trackId: 'server-track-1',
          schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
          albumYear: null,
          albumGenres: const <String>[],
          artistGenres: const <String>[],
        ),
      );

      final current = await storage.readMetadataRepairRequests(serverBaseUrl);
      expect(current, isEmpty);

      final dbPath = offlineTestJoin(
        offlineTestJoin(temp.path, 'offline'),
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
        final firstFile = await offlineTestMediaFile(temp, 'first.mp3');
        final secondFile = await offlineTestMediaFile(temp, 'second.mp3');
        final firstMetadata = offlineTestOfflineMetadata(
          trackId: 'server-one-track',
          artistSummary: 'First server artist summary.',
        );
        final secondMetadata = offlineTestOfflineMetadata(
          trackId: 'server-two-track',
          artistSummary: 'Second server artist summary.',
        );

        final first = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: firstMetadata.track,
            filePath: firstFile.path,
          ).copyWith(offlineMetadata: firstMetadata),
        );
        await storage.upsertDownload(first);
        final second = await storage.prepareDownload(
          offlineTestDownload(
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
      final firstMetadata = offlineTestOfflineMetadata(
        trackId: 'track-one',
        albumId: 'album-one',
        albumTitle: 'Album One',
        albumArtPath: albumOneArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final secondMetadata = offlineTestOfflineMetadata(
        trackId: 'track-two',
        albumId: 'album-two',
        albumTitle: 'Album Two',
        albumArtPath: albumTwoArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final first = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: firstMetadata.track,
          filePath: (await offlineTestMediaFile(temp, 'one.mp3')).path,
        ).copyWith(offlineMetadata: firstMetadata),
      );
      final second = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: secondMetadata.track,
          filePath: (await offlineTestMediaFile(temp, 'two.mp3')).path,
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
      final metadata = offlineTestOfflineMetadata(
        trackId: 'track-one',
        albumId: 'album-one',
        albumArtPath: albumArt.path,
        artistArtPath: artistLogo.path,
        artistBannerPath: artistBanner.path,
      );
      final download = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: metadata.track,
          filePath: (await offlineTestMediaFile(temp, 'one.mp3')).path,
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
        final metadata = offlineTestOfflineMetadata(
          trackId: 'track-one',
          albumId: 'album-one',
          albumArtPath: albumArt.path,
        );
        final download = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: metadata.track,
            filePath: (await offlineTestMediaFile(temp, 'one.mp3')).path,
          ).copyWith(offlineMetadata: metadata),
        );
        await storage.upsertDownload(download);

        final dbPath = offlineTestJoin(
          offlineTestJoin(temp.path, 'offline'),
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

    test(
      'startup repairs stale local artwork paths before garbage collection',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_startup_art_repair_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);

        final mediaFile = await offlineTestMediaFile(temp, 'completed.mp3');
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-1'),
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

        final oldArtRoot = offlineTestJoin(temp.path, 'old_container_art');
        await storage.updateTrackArtPaths(
          prepared.localTrackId!,
          albumArtPath: offlineTestJoin(oldArtRoot, 'album-1.png'),
          artistArtPath: offlineTestJoin(oldArtRoot, 'artist-1_logo.png'),
          artistBannerPath: offlineTestJoin(oldArtRoot, 'artist-1_banner.png'),
        );
        final dbPath = offlineTestJoin(
          offlineTestJoin(temp.path, 'offline'),
          'phonolite_offline.sqlite',
        );
        final db = sqlite3.open(dbPath);
        db.execute('DELETE FROM metadata WHERE key = ?', ['orphan_gc_v7']);
        db.execute(
          'INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)',
          ['schema_version', '6'],
        );
        db.dispose();

        final downloads = await storage.readDownloads();
        final localTracks = await storage.readLocalDownloadedTracks();
        final pendingDeletes = await storage.readPendingFileDeletes();

        expect(downloads.single.track.albumArtPath, albumArt.path);
        expect(downloads.single.track.artistArtPath, artistLogo.path);
        expect(downloads.single.track.artistBannerPath, artistBanner.path);
        expect(localTracks.single.albumArtPath, albumArt.path);
        expect(localTracks.single.artistArtPath, artistLogo.path);
        expect(localTracks.single.artistBannerPath, artistBanner.path);
        expect(await albumArt.exists(), isTrue);
        expect(await artistLogo.exists(), isTrue);
        expect(await artistBanner.exists(), isTrue);
        expect(pendingDeletes, isNot(contains(albumArt.path)));
        expect(pendingDeletes, isNot(contains(artistLogo.path)));
        expect(pendingDeletes, isNot(contains(artistBanner.path)));
      },
    );

    test('manager waits for initial load before queueing a batch', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_queue_load_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final delegate = OfflineLibraryStorage(baseDirectory: temp);
      final storage = DelayedReadStorage(delegate);
      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: 'http://server-one.test/api/v1'),
        storage: storage,
      );
      addTearDown(manager.dispose);

      final loadFuture = manager.load();
      var queued = false;
      final queueFuture = manager
          .queueBatch(
            offlineTestDownloadManifest(
              batchId: 'batch-load',
              trackId: 'server-track-1',
            ),
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
        offlineTestDownloadManifest(
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
      await offlineTestWaitFor(() async {
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
        offlineTestDownloadManifest(
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
      await offlineTestWaitFor(() async {
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
          offlineTestDownloadManifest(
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
        offlineTestDownloadManifest(
          batchId: 'batch-dedupe',
          trackId: 'server-track-1',
          itemCount: 25,
        ),
        label: 'Dedupe Album',
      );
      final secondQueued = await manager.queueBatch(
        offlineTestDownloadManifest(
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
      'artist queue rematerializes retryable tracks after missing files reload as corrupt',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_artist_retryable_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final connection = ArtistRetryTestConnection(
          baseUrl: serverBaseUrl,
          tracksByAlbum: <String, List<Track>>{
            'album-1': <Track>[offlineTestTrack(id: 'server-track-1')],
          },
          createBatch: (trackIds, clientBatchId) {
            return offlineTestDownloadManifest(
              batchId: clientBatchId ?? 'batch-artist-retryable',
              trackId: trackIds.first,
              byteLength: 4,
            );
          },
        )..setToken('token-1');
        final missingFile = offlineTestJoin(
          offlineTestJoin(temp.path, 'legacy'),
          'server-track-1.mp3',
        );
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            track: offlineTestTrack(id: 'server-track-1'),
            filePath: missingFile,
          ),
        );
        await storage.upsertDownload(prepared);

        final manager = OfflineDownloadManager(
          connection: connection,
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        expect(manager.downloads.single.status, OfflineDownloadStatus.corrupt);
        expect(manager.downloads.single.error, 'Completed file missing');

        final queued = await manager.queueArtist(
          Artist(id: 'artist-1', name: 'The Artist', albumCount: 1),
          <Album>[
            Album(
              id: 'album-1',
              title: 'The Album',
              artist: 'The Artist',
              artistId: 'artist-1',
              trackCount: 1,
            ),
          ],
        );

        expect(queued, 1);

        await offlineTestWaitFor(() async {
          final download = manager.downloads.singleWhere(
            (item) => item.track.id == 'server-track-1',
          );
          return download.status == OfflineDownloadStatus.queued &&
              download.batchId != null &&
              manager.jobs.isNotEmpty &&
              manager.jobs.single.materializedCount == 1;
        });

        final download = manager.downloads.singleWhere(
          (item) => item.track.id == 'server-track-1',
        );
        final jobItems = await storage.readDownloadJobItems(download.batchId!);

        expect(download.status, OfflineDownloadStatus.queued);
        expect(jobItems, hasLength(1));
        expect(jobItems.single.status, OfflineDownloadStatus.queued);
        expect(jobItems.single.materialized, isTrue);
      },
    );

    test('manager repairs stale downloaded file paths on load', () async {
      final temp = await Directory.systemTemp.createTemp(
        'phonolite_offline_repair_stale_path_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final storage = OfflineLibraryStorage(baseDirectory: temp);
      final serverBaseUrl = 'http://server-one.test/api/v1';
      final canonicalFile = await storage.trackFile(
        serverBaseUrl: serverBaseUrl,
        trackId: 'server-track-1',
        extension: 'mp3',
      );
      await canonicalFile.writeAsBytes(<int>[1, 2, 3]);
      final missingFile = offlineTestJoin(
        offlineTestJoin(temp.path, 'old_container'),
        'server-track-1.mp3',
      );
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: serverBaseUrl,
          track: offlineTestTrack(id: 'server-track-1'),
          filePath: missingFile,
        ).copyWith(contentType: 'audio/mpeg'),
      );
      await storage.upsertDownload(prepared);

      final manager = OfflineDownloadManager(
        connection: ServerConnection(baseUrl: serverBaseUrl),
        storage: storage,
      );
      addTearDown(manager.dispose);
      await manager.load();

      final download = manager.downloads.single;
      expect(download.status, OfflineDownloadStatus.downloaded);
      expect(download.filePath, canonicalFile.path);
      expect(download.error, isNull);
      expect(manager.localDownloadedTracks(), hasLength(1));
      expect(
        (await storage.readDownloads()).single.filePath,
        canonicalFile.path,
      );
    });

    test(
      'manager still marks missing downloaded files corrupt on load',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_missing_still_corrupt_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final missingFile = offlineTestJoin(
          offlineTestJoin(temp.path, 'old_container'),
          'server-track-1.mp3',
        );
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            track: offlineTestTrack(id: 'server-track-1'),
            filePath: missingFile,
          ).copyWith(contentType: 'audio/mpeg'),
        );
        await storage.upsertDownload(prepared);

        final manager = OfflineDownloadManager(
          connection: ServerConnection(baseUrl: serverBaseUrl),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        final download = manager.downloads.single;
        expect(download.status, OfflineDownloadStatus.corrupt);
        expect(download.filePath, isNull);
        expect(download.error, 'Completed file missing');
        expect(manager.localDownloadedTracks(), isEmpty);
      },
    );

    test(
      'manager repairs prior completed-file-missing corrupt records',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_repair_prior_corrupt_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final canonicalFile = await storage.trackFile(
          serverBaseUrl: serverBaseUrl,
          trackId: 'server-track-1',
          extension: 'mp3',
        );
        await canonicalFile.writeAsBytes(<int>[1, 2, 3]);
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            track: offlineTestTrack(id: 'server-track-1'),
            status: OfflineDownloadStatus.corrupt,
          ).copyWith(
            contentType: 'audio/mpeg',
            error: 'Completed file missing',
          ),
        );
        await storage.upsertDownload(prepared);

        final manager = OfflineDownloadManager(
          connection: ServerConnection(baseUrl: serverBaseUrl),
          storage: storage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        final download = manager.downloads.single;
        expect(download.status, OfflineDownloadStatus.downloaded);
        expect(download.filePath, canonicalFile.path);
        expect(download.error, isNull);
        expect(manager.localDownloadedTracks(), hasLength(1));
      },
    );

    test(
      'managed iOS storage migration copies legacy files and repairs paths',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_managed_migration_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final settingsFiles = offlineTestSettingsFiles(
          offlineTestJoin(temp.path, 'app_support'),
        );

        final legacyMetadata = Directory(
          offlineTestJoin(temp.path, 'legacy_metadata'),
        );
        final legacyDownloads = Directory(
          offlineTestJoin(temp.path, 'legacy_downloads'),
        );
        final legacySettings = OfflineStorageSettingsStorage(
          files: settingsFiles,
          usesManagedStoragePaths: () => false,
        );
        await legacySettings.write(
          OfflineStorageSettings(
            metadataDirectory: legacyMetadata.path,
            downloadsDirectory: legacyDownloads.path,
          ),
        );

        final serverBaseUrl = 'http://server-one.test/api/v1';
        final legacyStorage = OfflineLibraryStorage(
          metadataDirectory: legacyMetadata,
          downloadsDirectory: legacyDownloads,
        );
        final legacyFile = await legacyStorage.trackFile(
          serverBaseUrl: serverBaseUrl,
          trackId: 'server-track-1',
          extension: 'mp3',
        );
        await legacyFile.writeAsBytes(<int>[1, 2, 3]);
        final staleFilePath = offlineTestJoin(
          offlineTestJoin(temp.path, 'old_container'),
          'server-track-1.mp3',
        );
        final prepared = await legacyStorage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            track: offlineTestTrack(id: 'server-track-1'),
            filePath: staleFilePath,
          ).copyWith(contentType: 'audio/mpeg'),
        );
        await legacyStorage.upsertDownload(prepared);

        final managedStorage = ManagedTestStorage(
          defaultDirectoryProvider: settingsFiles.directoryProvider,
          settingsStorage: OfflineStorageSettingsStorage(
            files: settingsFiles,
            usesManagedStoragePaths: () => true,
          ),
        );
        final manager = OfflineDownloadManager(
          connection: ServerConnection(baseUrl: serverBaseUrl),
          storage: managedStorage,
        );
        addTearDown(manager.dispose);
        await manager.load();

        final managedFile = await managedStorage.trackFile(
          serverBaseUrl: serverBaseUrl,
          trackId: 'server-track-1',
          extension: 'mp3',
        );
        final download = manager.downloads.single;
        expect(await managedFile.exists(), isTrue);
        expect(download.status, OfflineDownloadStatus.downloaded);
        expect(download.filePath, managedFile.path);
        expect(
          (await managedStorage.readDownloads()).single.filePath,
          managedFile.path,
        );

        final normalizedSettings = await legacySettings.read();
        expect(normalizedSettings.metadataDirectory, isNull);
        expect(normalizedSettings.downloadsDirectory, isNull);
      },
    );

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
        final firstTrack = offlineTestTrack(id: 'server-track-1');
        final secondTrack = offlineTestTrack(
          id: 'server-track-2',
          title: 'Second Song',
        );
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
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: firstTrack,
            status: OfflineDownloadStatus.queued,
          ),
          offlineTestDownload(
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
      final firstTrack = offlineTestTrack(id: 'server-track-1');
      final secondTrack = offlineTestTrack(
        id: 'server-track-2',
        title: 'Second Song',
      );
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
        offlineTestDownload(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: firstTrack,
          status: OfflineDownloadStatus.queued,
        ),
        offlineTestDownload(
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
        final firstTrack = offlineTestTrack(id: 'server-track-1');
        final secondTrack = offlineTestTrack(
          id: 'server-track-2',
          title: 'Second Song',
        );
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
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            batchId: jobId,
            track: firstTrack,
            status: OfflineDownloadStatus.paused,
          ),
          offlineTestDownload(
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
      final firstFile = await offlineTestMediaFile(temp, 'first.mp3');
      final secondFile = await offlineTestMediaFile(temp, 'second.mp3');
      final firstTrack = offlineTestTrack(id: 'server-track-1');
      final secondTrack = offlineTestTrack(
        id: 'server-track-2',
        title: 'Second Song',
      );
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
        offlineTestDownload(
          serverBaseUrl: serverBaseUrl,
          batchId: jobId,
          track: firstTrack,
          filePath: firstFile.path,
        ),
        offlineTestDownload(
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

    test(
      'manager repairs stale metadata once when server metadata is empty',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'phonolite_offline_manager_metadata_repair_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final storage = OfflineLibraryStorage(baseDirectory: temp);
        var metadataRequestCount = 0;
        final serverBaseUrl = 'http://server-one.test/api/v1';
        final staleMetadata = offlineTestOfflineMetadata(
          trackId: 'server-track-1',
          albumTitle: 'Gorillaz',
          albumId: 'album-1',
          albumYear: null,
          albumGenres: const <String>[],
          schemaVersion: OfflineTrackMetadata.currentSchemaVersion - 1,
        );
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: serverBaseUrl,
            track: staleMetadata.track,
            filePath: (await offlineTestMediaFile(
              temp,
              'repair-auth.mp3',
            )).path,
          ).copyWith(offlineMetadata: staleMetadata),
        );
        await storage.upsertDownload(prepared);

        final connection = OfflineMetadataTestConnection(
          baseUrl: serverBaseUrl,
          metadata: offlineTestOfflineMetadata(
            trackId: 'server-track-1',
            albumTitle: 'Gorillaz',
            albumId: 'album-1',
            albumYear: null,
            albumGenres: const <String>[],
            artistGenres: const <String>[],
            schemaVersion: OfflineTrackMetadata.currentSchemaVersion,
          ),
          onMetadataRequested: () {
            metadataRequestCount += 1;
          },
        );
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

      final mediaFile = await offlineTestMediaFile(temp, 'completed.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(id: 'server-track-1'),
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

        final mediaFile = await offlineTestMediaFile(temp, 'completed.mp3');
        final partialFile = await offlineTestMediaFile(
          temp,
          'completed.mp3.part',
        );
        final prepared = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-1'),
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
        await offlineTestWaitFor(
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
      final missing = offlineTestJoin(temp.path, 'missing.mp3');
      final prepared = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'http://server-one.test/api/v1',
          track: offlineTestTrack(id: 'server-track-1'),
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

        final firstFile = await offlineTestMediaFile(temp, 'first.mp3');
        final secondFile = await offlineTestMediaFile(temp, 'second.mp3');
        final first = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-1'),
            filePath: firstFile.path,
          ),
        );
        final second = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://server-one.test/api/v1',
            track: offlineTestTrack(id: 'server-track-2', title: 'Second Song'),
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
      final mediaFile = await offlineTestMediaFile(temp, 'pending.mp3');
      final missingFile = File(offlineTestJoin(temp.path, 'already-gone.mp3'));
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

      await offlineTestWaitFor(
        () async =>
            !await mediaFile.exists() &&
            (await storage.readPendingFileDeletes()).isEmpty,
      );
      expect(await mediaFile.exists(), isFalse);
      expect(await storage.readPendingFileDeletes(), isEmpty);
    });
  });
}
