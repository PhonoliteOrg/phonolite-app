import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/api/artwork_urls.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

/// Catalog access and artwork resolution shared by feature controllers.
class CatalogController {
  final ServerConnection _connection;

  CatalogController(this._connection);

  String get baseUrl => _connection.baseUrl;

  int get sessionRevision => _connection.sessionRevision;

  Future<Album> fetchAlbumById(String id) => _connection.fetchAlbumById(id);

  Future<Artist> fetchArtistById(String id) => _connection.fetchArtistById(id);

  Future<Track> fetchTrackById(String id) => _connection.fetchTrackById(id);

  String buildAlbumCoverUrl(String id) => _connection.buildAlbumCoverUrl(id);

  String buildArtistCoverUrl(String id, {String? kind, String? ref}) =>
      _connection.buildArtistCoverUrl(id, kind: kind, ref: ref);

  String buildPlaylistCoverUrl(String id, {String? imageRef}) =>
      _connection.buildPlaylistCoverUrl(id, imageRef: imageRef);

  /// Uses the job's saved origin, which may differ from the active connection.
  static String? downloadJobCoverUrl(OfflineDownloadJob job) {
    final sourceId = job.sourceId?.trim();
    final baseUrl = job.serverBaseUrl.trim();

    if (sourceId == null || sourceId.isEmpty || baseUrl.isEmpty) {
      return null;
    }

    return switch (job.kind) {
      'artist' => ServerArtworkUrls.artistCover(baseUrl, sourceId, kind: 'logo'),
      'album' => ServerArtworkUrls.albumCover(baseUrl, sourceId),
      _ => null,
    };
  }

  /// Local artwork wins; remote artwork retains the download's original server.
  static String? downloadArtworkUrl(OfflineTrackDownload download) {
    final localPath = download.track.albumArtPath?.trim();

    if (localPath != null && localPath.isNotEmpty) {
      return localPath;
    }

    final albumId = download.track.albumId?.trim();
    final baseUrl = download.serverBaseUrl.trim();

    if (albumId == null || albumId.isEmpty || baseUrl.isEmpty) {
      return null;
    }

    return ServerArtworkUrls.albumCover(baseUrl, albumId);
  }

  Future<Track> resolveSearchTrack(
    SearchResult result, {
    required bool local,
    required Iterable<Track> offlineTracks,
  }) async {
    if (local) {
      return offlineTracks.firstWhere((track) => track.id == result.id || track.localId == result.id);
    }

    return fetchTrackById(result.id);
  }

  String? searchArtwork(SearchResult result) {
    switch (result.kind) {
      case 'artist':
        return buildArtistCoverUrl(result.id, kind: 'logo');
      case 'album':
        return buildAlbumCoverUrl(result.id);
      case 'track':
        final id = result.albumId?.trim();

        return id == null || id.isEmpty ? null : buildAlbumCoverUrl(id);
      default:
        return null;
    }
  }

  /// Older servers omit album_id in track search results.
  Future<String?> legacySearchArtwork(SearchResult result) async {
    if (result.kind != 'track' || (result.albumId?.trim().isNotEmpty ?? false)) {
      return searchArtwork(result);
    }

    try {
      final track = await fetchTrackById(result.id);
      final id = track.albumId;

      return id == null || id.isEmpty ? null : buildAlbumCoverUrl(id);
    } catch (_) {
      return null;
    }
  }
}
