import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

/// Artwork routes for an explicit server, including saved download origins.
class ServerArtworkUrls {
  static String playlistCover(String baseUrl, String playlistId, {String? imageRef}) {
    final encoded = ApiTransport.encodePathSegment(playlistId);
    var url = '$baseUrl/library/playlists/$encoded/cover';
    final ref = imageRef?.trim();

    if (ref != null && ref.isNotEmpty) {
      url = '$url?v=${Uri.encodeComponent(ref)}';
    }

    return url;
  }

  static String albumCover(String baseUrl, String albumId) {
    final encoded = ApiTransport.encodePathSegment(albumId);

    return '$baseUrl/library/albums/$encoded/cover';
  }

  static String artistCover(String baseUrl, String artistId, {String? kind, String? ref}) {
    final encoded = ApiTransport.encodePathSegment(artistId);
    var path = '/library/artists/$encoded/cover';

    if (kind != null && kind.isNotEmpty) {
      path = '$path?kind=${Uri.encodeComponent(kind)}';
    }

    if (ref != null && ref.trim().isNotEmpty) {
      path = '$path${path.contains('?') ? '&' : '?'}v=${Uri.encodeComponent(ref)}';
    }

    return '$baseUrl$path';
  }
}
