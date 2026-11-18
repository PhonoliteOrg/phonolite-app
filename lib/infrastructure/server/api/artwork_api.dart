import 'dart:async';
import 'dart:io';

import 'package:phonolite_app/data/models/server/server_artwork.dart';
import 'package:phonolite_app/data/models/server/api_exception.dart';
import 'package:phonolite_app/infrastructure/server/api/artwork_urls.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';
import 'package:phonolite_app/infrastructure/server/transport/streamed_response_body.dart';

typedef PlaylistCoverUrlBuilder = String Function(String playlistId, {String? imageRef});

typedef ArtistCoverUrlBuilder = String Function(String artistId, {String? kind, String? ref});

class ArtworkApi {
  static const int _maximumBytes = 16 * 1024 * 1024;

  final ApiTransport _transport;
  final String Function(String albumId) _albumCoverUrl;
  final PlaylistCoverUrlBuilder _playlistCoverUrl;
  final ArtistCoverUrlBuilder _artistCoverUrl;

  /// Callbacks retain the facade's override surface without importing its type.
  ArtworkApi(
    this._transport, {
    required this._albumCoverUrl,
    required this._playlistCoverUrl,
    required this._artistCoverUrl,
  });

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
    final uri = Uri.parse(url);
    final origin = Uri.parse(_transport.baseUrl);

    if (uri.userInfo.isNotEmpty ||
        !const ['http', 'https'].contains(uri.scheme) ||
        (!_transport.injectedClient && (uri.scheme != 'https' || uri.host != origin.host || uri.port != origin.port))) {
      throw const HttpException('Artwork origin is not the authenticated server');
    }

    final headers = _transport.buildHeaders();
    final revision = _transport.sessionRevision;
    final response = await _transport.executeRequest(
      () => _transport.sendStreamed(
        'GET',
        uri,
        timeout: timeout,
        configure: (request) => request
          ..followRedirects = false
          ..headers.addAll(headers),
      ),
      retryable: true,
      timeout: timeout,
      label: 'GET artwork',
      beforeRetry: () {
        if (_transport.sessionRevision != revision) {
          throw StateError('Artwork session changed');
        }
      },
    );
    final status = response.statusCode;

    if (_transport.sessionRevision != revision) {
      await discardResponseBody(response);

      throw StateError('Artwork session changed');
    }

    if (status < 200 || status >= 300 || status == 204) {
      await discardResponseBody(response);

      if (status == 404 || status == 204) {
        return null;
      }

      throw ApiException(status, 'Artwork request failed', retryAfter: const ApiResponseDecoder().retryAfter(response));
    }

    if ((response.contentLength ?? 0) > _maximumBytes) {
      await discardResponseBody(response);

      throw const HttpException('Artwork exceeds encoded byte limit');
    }

    final bytes = await readBoundedBody(
      response.stream,
      deadline: timeout,
      maximumBytes: _maximumBytes,
      tooLarge: (_) => const HttpException('Artwork exceeds encoded byte limit'),
    );

    if (_transport.sessionRevision != revision) {
      throw StateError('Artwork session changed');
    }

    return bytes.isEmpty
        ? null
        : ServerArtwork(bytes: bytes, contentType: response.headers[HttpHeaders.contentTypeHeader]);
  }
}
