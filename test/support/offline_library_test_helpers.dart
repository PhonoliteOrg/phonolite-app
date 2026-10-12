import 'dart:async';
import 'dart:io';

import 'package:phonolite_app/persistence/settings_files.dart';

import 'package:phonolite_app/entities/models.dart';
import 'package:phonolite_app/entities/offline_library.dart';
import 'package:phonolite_app/entities/server_connection.dart';

Track offlineTestTrack({
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

OfflineTrackDownload offlineTestDownload({
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

DownloadBatchManifest offlineTestDownloadManifest({
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
            track: offlineTestTrack(id: id),
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

OfflineTrackMetadata offlineTestOfflineMetadata({
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
    track: offlineTestTrack(
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

class DelayedReadStorage extends OfflineLibraryStorage {
  DelayedReadStorage(this.delegate);

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

class ManagedTestStorage extends OfflineLibraryStorage {
  const ManagedTestStorage({
    required super.settingsStorage,
    super.defaultDirectoryProvider,
  });
}

Future<File> offlineTestMediaFile(Directory temp, String name) async {
  final dir = Directory(
    offlineTestJoin(offlineTestJoin(temp.path, 'offline'), 'test_media'),
  );
  await dir.create(recursive: true);
  final file = File(offlineTestJoin(dir.path, name));
  await file.writeAsBytes(<int>[1, 2, 3]);
  return file;
}

String offlineTestJoin(String left, String right) {
  final separator = Platform.pathSeparator;
  if (left.endsWith(separator)) {
    return '$left$right';
  }
  return '$left$separator$right';
}

Future<void> offlineTestWaitFor(
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

SettingsFiles offlineTestSettingsFiles(String appSupportPath) => SettingsFiles(
  directoryProvider: () async =>
      Directory(offlineTestJoin(appSupportPath, 'Phonolite')),
);

class SingleBatchTestConnection extends ServerConnection {
  SingleBatchTestConnection({
    required super.baseUrl,
    required this.manifest,
    this.onBatchRequested,
  });

  final DownloadBatchManifest manifest;
  final void Function()? onBatchRequested;

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    onBatchRequested?.call();
    return manifest;
  }
}

class OfflineMetadataTestConnection extends ServerConnection {
  OfflineMetadataTestConnection({
    required super.baseUrl,
    required this.metadata,
    this.onMetadataRequested,
  });

  final OfflineTrackMetadata metadata;
  final void Function()? onMetadataRequested;

  @override
  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    onMetadataRequested?.call();
    return metadata;
  }
}

class ArtistRetryTestConnection extends ServerConnection {
  ArtistRetryTestConnection({
    required super.baseUrl,
    required this.tracksByAlbum,
    required this.createBatch,
  });

  final Map<String, List<Track>> tracksByAlbum;
  final DownloadBatchManifest Function(
    List<String> trackIds,
    String? clientBatchId,
  )
  createBatch;

  @override
  Future<ServerCapabilities> fetchCapabilities() async {
    return ServerCapabilities(
      downloadJobsV2: false,
      metadataSnapshotsV2: false,
      eventReplayV2: false,
      trackFileContractV2: false,
    );
  }

  @override
  Future<List<Track>> fetchTracks(String albumId) async {
    return tracksByAlbum[albumId] ?? const <Track>[];
  }

  @override
  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    setToken(null);
    return createBatch(trackIds, clientBatchId);
  }
}
