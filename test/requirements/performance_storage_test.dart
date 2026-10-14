import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_library.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final keepDatabaseOpen in [false, true]) {
    test(
      'client identity preserves download writes with keepDatabaseOpen=$keepDatabaseOpen',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'phonolite_client_identity_downloads_',
        );
        final storage = OfflineLibraryStorage(
          baseDirectory: root,
          keepDatabaseOpen: keepDatabaseOpen,
        );
        addTearDown(() async {
          await storage.close();
          await root.delete(recursive: true);
        });

        final clientId = await storage.readOrCreateClientId();
        expect(clientId, isNotEmpty);
        // A later download request also reads the existing client identity.
        expect(await storage.readOrCreateClientId(), clientId);

        final media = await offlineTestMediaFile(root, 'completed.mp3');
        final download = await storage.prepareDownload(
          offlineTestDownload(
            serverBaseUrl: 'http://unused.test/api/v1',
            track: offlineTestTrack(id: 'song'),
            filePath: media.path,
          ),
        );
        expect(download.localTrackId, isNotNull);
        await storage.upsertDownload(download);

        expect(await storage.readDownloads(), hasLength(1));
        final tracks = await storage.readLocalDownloadedTracks();
        expect(tracks, hasLength(1));
        expect(tracks.single.localId, download.localTrackId);
        await storage.close();
        expect(await storage.readOrCreateClientId(), clientId);
        expect(await storage.readLocalDownloadedTracks(), hasLength(1));
      },
    );
  }

  test(
    'worker database survives repeated operations and closes before reset',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite_storage_reuse_',
      );
      final storage = OfflineLibraryStorage(
        baseDirectory: root,
        keepDatabaseOpen: true,
      );
      addTearDown(() async {
        await storage.close();
        await root.delete(recursive: true);
      });
      final audio = File('${root.path}/song.mp3');
      await audio.writeAsBytes([1, 2, 3]);
      final download = await storage.prepareDownload(
        OfflineTrackDownload(
          serverBaseUrl: 'http://unused.test/api/v1',
          track: Track(
            id: 'song',
            title: 'Song',
            artist: 'Artist',
            album: 'Album',
            durationMs: 1000,
            liked: false,
            inPlaylists: false,
          ),
          status: OfflineDownloadStatus.downloaded,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          filePath: audio.path,
          bytesDownloaded: 3,
          bytesTotal: 3,
        ),
      );
      await storage.upsertDownload(download);
      await storage.setLocalLike(download.localTrackId!, true);
      final lists = await Future.wait([
        storage.readLocalDownloadedTracks(),
        storage.readLocalLikedTracks(),
      ]);
      expect(lists.every((tracks) => tracks.length == 1), isTrue);
      await storage.close();
      expect(await storage.readLocalLikedTracks(), hasLength(1));
      await storage.resetLocalData();
      expect(await storage.readDownloads(), isEmpty);
    },
  );
}
