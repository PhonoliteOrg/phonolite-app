import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('persistence and helper source contracts', () {
    test('auth storage persists expected fields and file location rules', () {
      final source = readProjectFile('lib/entities/auth_storage.dart');

      expectContainsAll(source, const [
        "static const String _fileName = 'auth.json';",
        "'baseUrl': baseUrl",
        "'token': token",
        "'username': username",
        "Platform.environment['APPDATA']",
        "getApplicationSupportDirectory()",
        "'Phonolite'",
      ]);
    });

    test('playback preferences persist volume and collection mode', () {
      final source = readProjectFile('lib/entities/playback_preferences.dart');

      expectContainsAll(source, const [
        "static const String _fileName = 'playback_prefs.json';",
        "static const String _volumeKey = 'volume';",
        "static const String _collectionListModeKey = 'collection_list_mode';",
        'writeVolume(double volume)',
        'writeCollectionListMode(bool value)',
        "Platform.environment['APPDATA']",
      ]);
    });

    test('custom shuffle settings persist from cache and normalize values', () {
      final source = readProjectFile(
        'lib/entities/custom_shuffle_settings.dart',
      );

      expectContainsAll(source, const [
        "static const String _fileName = 'shuffle_settings.json';",
        'text = text.toLowerCase();',
        'getApplicationCacheDirectory()',
        "Platform.environment['LOCALAPPDATA']",
        'getApplicationSupportDirectory()',
      ]);
    });

    test('offline library storage records server downloads and file paths', () {
      final source = readProjectFile('lib/entities/offline_library.dart');

      expectContainsAll(source, const [
        'enum OfflineDownloadStatus {',
        'preparing,',
        'paused,',
        'validating,',
        'corrupt,',
        'canceled,',
        'class OfflineDownloadBatch',
        'enum OfflineDeletionScopeKind',
        'class OfflineDeletionScope',
        'class OfflineDeletionRequest',
        'class OfflineDeletionResult',
        "static const String _rootDirName = 'offline';",
        "static const String _tracksDirName = 'tracks';",
        "static const String _artDirName = 'art';",
        "static const String _indexFileName = 'offline_library.json';",
        "static const String _databaseFileName = 'phonolite_offline.sqlite';",
        'final Directory? metadataDirectory;',
        'final Directory? downloadsDirectory;',
        'Future<OfflineStorageLocations> resolveStorageLocations() async',
        'Future<void> updateStorageLocations({',
        'Future<void> resetLocalData() async',
        'Future<Directory> metadataRoot({bool createDir = false}) async',
        'Future<Directory> downloadsRoot({bool createDir = false}) async',
        'CREATE TABLE IF NOT EXISTS tracks',
        'album_art_path TEXT',
        'artist_art_path TEXT',
        'artist_banner_path TEXT',
        'CREATE TABLE IF NOT EXISTS source_tracks',
        'CREATE TABLE IF NOT EXISTS download_batches',
        'CREATE TABLE IF NOT EXISTS download_items',
        'CREATE TABLE IF NOT EXISTS pending_file_deletes',
        'expected_sha256 TEXT',
        'retry_count INTEGER NOT NULL DEFAULT 0',
        'CREATE TABLE IF NOT EXISTS local_likes',
        'CREATE TABLE IF NOT EXISTS local_playlists',
        'description TEXT',
        'image_path TEXT',
        'CREATE TABLE IF NOT EXISTS local_playlist_tracks',
        'Future<OfflineTrackDownload> prepareDownload(',
        'Future<List<OfflineTrackDownload>> readDownloads()',
        'Future<List<OfflineDownloadBatch>> readDownloadBatches()',
        'Future<void> upsertDownloadBatch(OfflineDownloadBatch batch)',
        'Future<void> removeDownloads(',
        'Future<OfflineDeletionResult> removeDownloadsScoped(',
        'Future<void> recordPendingFileDeletes(',
        'Future<bool> isManagedDeletePath(String path) async',
        'PRAGMA busy_timeout = 5000',
        "trim(f.track_json) = ''",
        'json_valid(f.track_json) = 0',
        'Future<List<String>> readPendingFileDeletes()',
        'Future<void> clearPendingFileDeletes(',
        'Future<List<Track>> readLocalDownloadedTracks()',
        'Future<List<Track>> readLocalLikedTracks()',
        'Future<List<Playlist>> readLocalPlaylists()',
        'Future<void> upsertDownload(OfflineTrackDownload download)',
        'Future<void> updateTrackArtPaths(',
        'Future<void> setLocalLike(String localTrackId, bool liked)',
        'Future<Playlist?> addLocalTrackToPlaylist(',
        'Future<Playlist?> updateLocalPlaylistImage(',
        'Future<void> _migrateJsonIndexIfNeeded(Database db) async',
        'Future<void> _runStartupGarbageCollection(Database db) async',
        'Future<List<String>> _unusedArtworkFiles(',
        'void _ensureColumn(',
        '_metadataMatchKey(Track track)',
        '(duration - track.durationMs).abs() <= 2000',
        'Future<File> trackFile({',
        'Future<File> albumArtFile({',
        'Future<File> artistArtFile({',
        'Future<File> playlistArtFile({',
        "Platform.environment['LOCALAPPDATA']",
        'extensionFromContentType(String? contentType)',
        'extensionFromImageContentType(String? contentType)',
        'extensionFromContentDisposition(String? contentDisposition)',
        'base64Url.encode(utf8.encode(baseUrl.trim()))',
      ]);
    });

    test(
      'offline storage settings persist separate metadata and download roots',
      () {
        final source = readProjectFile(
          'lib/entities/offline_storage_settings.dart',
        );

        expectContainsAll(source, const [
          'class OfflineStorageSettings',
          'class OfflineStorageLocations',
          "static const String _fileName = 'offline_storage.json';",
          "'metadata_directory': metadataDirectory",
          "'downloads_directory': downloadsDirectory",
          "Platform.environment['APPDATA']",
          "getApplicationSupportDirectory()",
        ]);
      },
    );

    test('offline download manager resumes and promotes track downloads', () {
      final source = readProjectFile(
        'lib/entities/offline_download_manager.dart',
      );

      expectContainsAll(source, const [
        'class OfflineDownloadManager',
        'static const int maxParallelDownloadsPerServer = 1;',
        'static const Duration _progressEmitInterval = Duration(seconds: 3);',
        'static const int _queuePersistChunkSize = 20;',
        'static const Duration _queuePersistYieldDelay = Duration(milliseconds: 8);',
        'static const int _maxParallelFileDeletes = 4;',
        'final Map<String, Future<void>> _active',
        'final Set<String> _removedDownloadKeys',
        'Stream<List<OfflineTrackDownload>> get stream',
        'Stream<List<OfflineDownloadBatch>> get batchStream',
        'Stream<List<Track>> get localLikedStream',
        'Stream<List<Playlist>> get localPlaylistsStream',
        'Future<int> downloadTrack(Track track)',
        'Future<int> queueBatch(',
        'Future<void> _ensureLoaded() async',
        'Future<void> pauseDownloadsForServer(String serverBaseUrl)',
        'Future<void> resumePausedForCurrentServer()',
        'Future<void> repairOfflineMetadataFragments()',
        'Future<void> refreshOfflineMetadataForAlbum(String albumId)',
        'Future<void> refreshOfflineMetadataForArtist(String artistId)',
        'static const int _metadataRepairMaxPerRun',
        'Future<Set<String>> _repairOfflineMetadataRequests(',
        'Future<void> clearFailedAndCorrupt()',
        'Future<void> resetLocalData()',
        'Future<void> removeDownloads(',
        'OfflineDeletionScope scope = const OfflineDeletionScope.track()',
        'Future<void> _cleanupPendingFileDeletes()',
        'Skipping unmanaged pending delete path outside offline storage',
        'readPendingFileDeletes()',
        'clearPendingFileDeletes(',
        'Future<void> setLocalLike(Track track, bool liked)',
        'Future<Playlist> createLocalPlaylist(',
        'description: description',
        'Future<Playlist?> updateLocalPlaylistImage(',
        'Future<Playlist?> addLocalTrackToPlaylist(',
        'List<Track> localDownloadedTracks()',
        'final Map<String, SendPort> _activeCancelPorts',
        'Isolate.spawn(',
        '_downloadWorkerMain',
        'connection.buildTrackDownloadUrl(_serverTrackId(download))',
        'startByte: bytesDownloaded > 0 ? bytesDownloaded : null',
        'ifRange: bytesDownloaded > 0 ? download.etag : null',
        'response.statusCode == HttpStatus.partialContent',
        'HttpClient()',
        '_queueArtworkHydration(completed);',
        'Future<void> _drainArtworkHydrationQueue() async',
        'connection.fetchAlbumCoverBytes(id)',
        'connection.fetchArtistCoverBytes(id, kind: kind)',
        'OfflineLibraryStorage.extensionFromImageContentType(',
        'updateTrackArtPaths(',
        'sha256.bind(File(path).openRead()).first',
        'OfflineDownloadStatus.validating',
        'OfflineDownloadStatus.corrupt',
        'OfflineLibraryStorage.extensionFromContentDisposition(',
        'OfflineLibraryStorage.extensionFromContentType(',
        'partialFile.rename(finalFile.path)',
        'OfflineDownloadStatus.downloaded',
      ]);
    });

    test('library helpers disable expensive image work on web and windows', () {
      final source = readProjectFile('lib/core/library_helpers.dart');

      expectContainsAll(source, const [
        "return {'Authorization': 'Bearer \$token'};",
        'if (kIsWeb) {',
        'return defaultTargetPlatform != TargetPlatform.windows;',
      ]);
    });

    test('application logger preserves buffer size and trim policy', () {
      final source = readProjectFile('lib/entities/app_log.dart');

      expectContainsAll(source, const [
        'enum LogLevel { info, status, warning, error, debug }',
        'static const int _maxBuffer = 3000;',
        'static const int _trimChunk = 500;',
        'void attach(LogListener listener, {bool includeHistory = true})',
      ]);
    });
  });
}
