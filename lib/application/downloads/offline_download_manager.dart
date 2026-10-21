import 'dart:async';

import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/download_batch_manifest.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';
import 'package:phonolite_app/infrastructure/downloads/client/offline_download_client.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

export 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
export 'package:phonolite_app/data/models/library/offline_library_snapshot.dart';

/// Application access to the download client's current state and commands.
///
/// Snapshot streams are asynchronous broadcasts without initial replay. Read
/// [downloadSnapshot] or [librarySnapshot] for immediate observation; a read and
/// subscription are separate operations. Commands retain their own completion
/// and failure futures. [dispose] closes the client and its streams.
class OfflineDownloadManager {
  static const int maxParallelDownloadsPerServer = OfflineDownloadClient.maxParallelDownloadsPerServer;

  final OfflineDownloadClient _client;

  OfflineDownloadManager({
    required ServerConnection connection,
    OfflineLibraryStorage storage = const OfflineLibraryStorage(),
  }) : _client = OfflineDownloadClient(connection: connection, storage: storage);

  ServerConnection get connection => _client.connection;

  Stream<List<OfflineTrackDownload>> get stream => _client.stream;

  Stream<List<OfflineDownloadBatch>> get batchStream => _client.batchStream;

  Stream<List<OfflineDownloadJob>> get jobStream => _client.jobStream;

  Stream<OfflineDownloadSnapshot> get downloadSnapshotStream => _client.downloadSnapshotStream;

  Stream<OfflineLibrarySnapshot> get librarySnapshotStream => _client.librarySnapshotStream;

  Stream<List<Track>> get localLikedStream => _client.localLikedStream;

  Stream<List<Playlist>> get localPlaylistsStream => _client.localPlaylistsStream;

  Stream<List<Track>> get localPlaylistTracksStream => _client.localPlaylistTracksStream;

  List<OfflineTrackDownload> get downloads => _client.downloads;

  List<OfflineDownloadBatch> get batches => _client.batches;

  List<OfflineDownloadJob> get jobs => _client.jobs;

  OfflineDownloadSnapshot get downloadSnapshot => _client.downloadSnapshot;

  OfflineLibrarySnapshot get librarySnapshot => _client.librarySnapshot;

  List<Track> get localLiked => _client.localLiked;

  List<Playlist> get localPlaylists => _client.localPlaylists;

  List<Track> get localPlaylistTracks => _client.localPlaylistTracks;

  Future<void> dispose() => _client.dispose();

  Future<void> load() => _client.load();

  OfflineTrackDownload? findForCurrentServer(String trackId) => _client.findForCurrentServer(trackId);

  OfflineTrackDownload? find(String serverBaseUrl, String trackId) => _client.find(serverBaseUrl, trackId);

  OfflineTrackDownload? findLocal(String localTrackId) => _client.findLocal(localTrackId);

  List<Track> localDownloadedTracks() => _client.localDownloadedTracks();

  Future<int> downloadTrack(Track track) => _client.downloadTrack(track);

  Future<int> queueTracks(Iterable<Track> tracks, {String? label, String kind = 'tracks', String? sourceId}) =>
      _client.queueTracks(tracks, label: label, kind: kind, sourceId: sourceId);

  Future<int> queueBatch(DownloadBatchManifest manifest, {String? label}) => _client.queueBatch(manifest, label: label);

  Future<int> queueArtist(Artist artist, List<Album> albums) => _client.queueArtist(artist, albums);

  Future<void> pauseDownload(OfflineTrackDownload download) => _client.pauseDownload(download);

  Future<void> resumeDownload(OfflineTrackDownload download) => _client.resumeDownload(download);

  Future<void> retryDownload(OfflineTrackDownload download) => _client.retryDownload(download);

  Future<void> cancelDownload(OfflineTrackDownload download) => _client.cancelDownload(download);

  Future<void> pauseDownloadsForServer(String serverBaseUrl) => _client.pauseDownloadsForServer(serverBaseUrl);

  Future<void> resumePausedForCurrentServer() => _client.resumePausedForCurrentServer();

  Future<void> repairOfflineMetadataFragments() => _client.repairOfflineMetadataFragments();

  Future<void> refreshOfflineMetadataForAlbum(String albumId) => _client.refreshOfflineMetadataForAlbum(albumId);

  Future<void> refreshOfflineMetadataForArtist(String artistId) => _client.refreshOfflineMetadataForArtist(artistId);

  Future<void> pauseDownloadJob(OfflineDownloadJob job) => _client.pauseDownloadJob(job);

  Future<void> resumeDownloadJob(OfflineDownloadJob job) => _client.resumeDownloadJob(job);

  Future<void> cancelDownloadJob(OfflineDownloadJob job) => _client.cancelDownloadJob(job);

  Future<void> removeTrack(String trackId) => _client.removeTrack(trackId);

  Future<void> removeDownload(OfflineTrackDownload download) => _client.removeDownload(download);

  Future<void> removeDownloads(
    Iterable<OfflineTrackDownload> downloads, {
    OfflineDeletionScope scope = const OfflineDeletionScope.track(),
  }) => _client.removeDownloads(downloads, scope: scope);

  Future<void> clearFailedAndCorrupt() => _client.clearFailedAndCorrupt();

  Future<void> resetLocalData() => _client.resetLocalData();

  Future<void> clearUnfinishedDownloads() => _client.clearUnfinishedDownloads();

  Future<void> loadLocalPlaylists() => _client.loadLocalPlaylists();

  Future<void> loadLocalPlaylistTracks(String playlistId) => _client.loadLocalPlaylistTracks(playlistId);

  Future<void> loadLocalLikedTracks() => _client.loadLocalLikedTracks();

  Future<void> setLocalLike(Track track, bool liked) => _client.setLocalLike(track, liked);

  Future<List<LocalLikeState>> readLocalLikeStates() => _client.readLocalLikeStates();

  Future<Playlist> createLocalPlaylist(String name, {String? description}) =>
      _client.createLocalPlaylist(name, description: description);

  Future<Playlist> downloadPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    required String name,
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _client.downloadPlaylist(playlist, tracks, name: name, description: description, imageEdit: imageEdit);

  Future<Playlist?> renameLocalPlaylist(String playlistId, String name, {String? description}) =>
      _client.renameLocalPlaylist(playlistId, name, description: description);

  Future<Playlist?> updateLocalPlaylistImage(String playlistId, PlaylistImageEdit imageEdit) =>
      _client.updateLocalPlaylistImage(playlistId, imageEdit);

  Future<void> deleteLocalPlaylist(String playlistId) => _client.deleteLocalPlaylist(playlistId);

  Future<Playlist?> addLocalTrackToPlaylist(Playlist playlist, Track track) =>
      _client.addLocalTrackToPlaylist(playlist, track);

  Future<Playlist?> removeLocalTrackFromPlaylist(Playlist playlist, Track track) =>
      _client.removeLocalTrackFromPlaylist(playlist, track);
}
