import 'dart:async';
import 'dart:io';

import 'package:phonolite_app/data/models/server/server_artwork.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/api/artwork_urls.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

typedef PlaylistCoverUrlBuilder = String Function(String playlistId, {String? imageRef});

typedef ArtistCoverUrlBuilder = String Function(String artistId, {String? kind, String? ref});

class ArtworkApi {
  final ApiTransport _transport;
  final String Function(String albumId) _albumCoverUrl;
  final PlaylistCoverUrlBuilder _playlistCoverUrl;
  final ArtistCoverUrlBuilder _artistCoverUrl;

  /// Callbacks retain the facade's override surface without importing its type.
  ArtworkApi(
    this._transport, {
    required String Function(String albumId) albumCoverUrl,
    required PlaylistCoverUrlBuilder playlistCoverUrl,
    required ArtistCoverUrlBuilder artistCoverUrl,
  }) : _albumCoverUrl = albumCoverUrl,
       _playlistCoverUrl = playlistCoverUrl,
       _artistCoverUrl = artistCoverUrl;

  String buildPlaylistCoverUrl(String playlistId, {String? imageRef}) =>
      ServerArtworkUrls.playlistCover(_transport.baseUrl, playlistId, imageRef: imageRef);

  String buildAlbumCoverUrl(String albumId) => ServerArtworkUrls.albumCover(_transport.baseUrl, albumId);

  String buildArtistCoverUrl(String artistId, {String? kind, String? ref}) =>
      ServerArtworkUrls.artistCover(_transport.baseUrl, artistId, kind: kind, ref: ref);

  Future<ServerArtwork?> fetchAlbumCoverBytes(String albumId, {Duration timeout = ApiTransport.defaultRequestTimeout}) {
    return fetchArtworkUrl(_albumCoverUrl(albumId), timeout: timeout);
  }

  Future<ServerArtwork?> fetchPlaylistCoverBytes(
    String playlistId, {
    String? imageRef,
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) {
    return fetchArtworkUrl(_playlistCoverUrl(playlistId, imageRef: imageRef), timeout: timeout);
  }

  Future<ServerArtwork?> fetchArtistCoverBytes(
    String artistId, {
    String kind = 'logo',
    Duration timeout = ApiTransport.defaultRequestTimeout,
  }) {
    return fetchArtworkUrl(_artistCoverUrl(artistId, kind: kind), timeout: timeout);
  }

  Future<ServerArtwork?> fetchArtworkUrl(String url, {required Duration timeout}) async {
    final response = await _transport.executeRequest(
      () => _transport.client.get(Uri.parse(url), headers: _transport.buildHeaders()),
      label: 'GET artwork',
      retryable: true,
      timeout: timeout,
    );

    if (response.statusCode == 404 || response.statusCode == 204) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }

    if (response.bodyBytes.isEmpty) {
      return null;
    }

    return ServerArtwork(bytes: response.bodyBytes, contentType: response.headers[HttpHeaders.contentTypeHeader]);
  }
}
