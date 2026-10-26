import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
    final uri = Uri.parse(url);
    final origin = Uri.parse(_transport.baseUrl);

    if (uri.userInfo.isNotEmpty ||
        !const ['http', 'https'].contains(uri.scheme) ||
        (!_transport.injectedClient && (uri.scheme != 'https' || uri.host != origin.host || uri.port != origin.port))) {
      throw const HttpException('Artwork origin is not the authenticated server');
    }

    final headers = _transport.buildHeaders();
    final revision = _transport.sessionRevision;

    for (var attempt = 1; attempt <= ApiTransport.maxGetAttempts; attempt++) {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(headers);
      final response = await _transport.client.send(request).timeout(timeout);
      final status = response.statusCode;

      if (status < 200 || status >= 300 || status == 204) {
        await response.stream.listen((_) {}).cancel();

        if (status == 404 || status == 204) {
          return null;
        }

        if ((status >= 500 || status == 429) && attempt < ApiTransport.maxGetAttempts) {
          final seconds = int.tryParse(response.headers[HttpHeaders.retryAfterHeader] ?? '');
          await Future<void>.delayed(
            seconds == null ? _transport.retryDelay(attempt) : Duration(seconds: seconds.clamp(1, 60)),
          );

          if (_transport.sessionRevision != revision) {
            throw StateError('Artwork session changed');
          }

          continue;
        }

        throw ApiException(status, 'Artwork request failed');
      }

      const maximumBytes = 16 * 1024 * 1024;

      if ((response.contentLength ?? 0) > maximumBytes) {
        await response.stream.listen((_) {}).cancel();

        throw const HttpException('Artwork exceeds encoded byte limit');
      }

      final bytes = BytesBuilder(copy: false);
      final elapsed = Stopwatch()..start();
      final chunks = StreamIterator(response.stream);

      try {
        while (true) {
          final remaining = timeout - elapsed.elapsed;

          if (remaining <= Duration.zero) {
            throw TimeoutException('Artwork body deadline exceeded');
          }

          if (!await chunks.moveNext().timeout(remaining)) {
            break;
          }

          if (bytes.length + chunks.current.length > maximumBytes) {
            throw const HttpException('Artwork exceeds encoded byte limit');
          }

          bytes.add(chunks.current);
        }
      } finally {
        await chunks.cancel();
      }

      if (_transport.sessionRevision != revision) {
        throw StateError('Artwork session changed');
      }

      return bytes.isEmpty
          ? null
          : ServerArtwork(bytes: bytes.takeBytes(), contentType: response.headers[HttpHeaders.contentTypeHeader]);
    }

    throw StateError('Artwork retry budget exhausted');
  }
}
