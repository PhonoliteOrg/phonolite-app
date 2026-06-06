import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class RequestTimeoutException implements Exception {
  RequestTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'Request timed out after ${timeout.inSeconds}s';
}

class TrackDownloadStream {
  TrackDownloadStream({
    required this.statusCode,
    required this.stream,
    this.contentLength,
    this.contentRange,
    this.contentType,
    this.contentDisposition,
    this.etag,
    this.sha256,
  });

  final int statusCode;
  final Stream<List<int>> stream;
  final int? contentLength;
  final String? contentRange;
  final String? contentType;
  final String? contentDisposition;
  final String? etag;
  final String? sha256;
}

class ServerArtwork {
  ServerArtwork({required this.bytes, this.contentType});

  final List<int> bytes;
  final String? contentType;
}

class ServerConnection {
  static const int artistsPageSize = 60;
  static const Duration _defaultRequestTimeout = Duration(seconds: 8);
  static const Duration _healthRequestTimeout = Duration(seconds: 2);
  static const Duration _slowRequestThreshold = Duration(milliseconds: 1200);
  static const int _maxGetAttempts = 3;

  ServerConnection({required String baseUrl, http.Client? client})
    : _baseUrl = _sanitizeBaseUrl(baseUrl),
      _client = client ?? http.Client();

  String _baseUrl;
  final http.Client _client;
  final Random _retryJitter = Random();
  String? _token;

  String get baseUrl => _baseUrl;
  String? get token => _token;

  void setBaseUrl(String baseUrl) {
    _baseUrl = _sanitizeBaseUrl(baseUrl);
  }

  Future<String> resolveBaseUrl(String input) async {
    final trimmed = _sanitizeInput(input);
    if (trimmed.isEmpty) {
      throw Exception('Server URL is required');
    }
    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    final candidates = hasScheme
        ? <String>[trimmed]
        : <String>['http://$trimmed', 'https://$trimmed'];

    for (final candidate in candidates) {
      final baseUrl = _ensureApiBase(candidate);
      final rootUrl = _ensureRoot(baseUrl);
      final ok = await _checkHealth(rootUrl) || await _checkHealth(baseUrl);
      if (ok) {
        return baseUrl;
      }
    }

    throw Exception('Unable to reach server');
  }

  void setToken(String? token) {
    _token = token;
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await _post('/auth/login', {
      'username': username,
      'password': password,
    });
    final token = response['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Missing token in login response');
    }
    _token = token;
    return token;
  }

  Future<void> logout() async {
    await _postVoid('/auth/logout', {});
  }

  Future<List<Artist>> fetchArtistsPage({
    int limit = ServerConnection.artistsPageSize,
    int offset = 0,
  }) async {
    final response = await _getList(
      '/browse/artists?limit=$limit&offset=$offset',
    );
    return response.map((item) => Artist.fromJson(item)).toList();
  }

  Future<List<Artist>> fetchArtists({
    int limit = ServerConnection.artistsPageSize,
  }) async {
    var offset = 0;
    final artists = <Artist>[];
    while (true) {
      final page = await fetchArtistsPage(limit: limit, offset: offset);
      artists.addAll(page);
      if (page.length < limit) {
        break;
      }
      offset += page.length;
    }
    return artists;
  }

  Future<List<Album>> fetchAlbums(String artistId) async {
    final encoded = _encodePathSegment(artistId);
    final response = await _getList('/browse/artists/$encoded/albums');
    return response.map((item) => Album.fromJson(item)).toList();
  }

  Future<List<Track>> fetchTracks(String albumId) async {
    final encoded = _encodePathSegment(albumId);
    final response = await _getList('/browse/albums/$encoded/tracks');
    return response.map((item) => Track.fromJson(item)).toList();
  }

  Future<List<Playlist>> fetchPlaylists() async {
    final response = await _getList('/library/playlists');
    return response.map((item) => Playlist.fromJson(item)).toList();
  }

  Future<List<Track>> fetchPlaylistTracks(String playlistId) async {
    final encoded = _encodePathSegment(playlistId);
    final response = await _getList('/browse/playlists/$encoded/tracks');
    return response.map((item) => Track.fromJson(item)).toList();
  }

  Future<List<Track>> fetchLikedTracks() async {
    final response = await _getList('/browse/likes');
    return response.map((item) => Track.fromJson(item)).toList();
  }

  Future<List<Track>> fetchShuffleTracks({
    required String mode,
    String? artistId,
    String? albumId,
    List<String>? artistIds,
    List<String>? genres,
  }) async {
    var path = '/library/shuffle?mode=$mode';
    if (artistId != null && artistId.isNotEmpty) {
      path = '$path&artist_id=${Uri.encodeComponent(artistId)}';
    }
    if (albumId != null && albumId.isNotEmpty) {
      path = '$path&album_id=${Uri.encodeComponent(albumId)}';
    }
    if (artistIds != null && artistIds.isNotEmpty) {
      final joined = Uri.encodeComponent(artistIds.join(','));
      path = '$path&artist_ids=$joined';
    }
    if (genres != null && genres.isNotEmpty) {
      final joined = Uri.encodeComponent(genres.join(','));
      path = '$path&genres=$joined';
    }
    final response = await _getList(path);
    return response.map((item) => Track.fromJson(item)).toList();
  }

  Future<StatsResponse> fetchStats({int? year, int? month}) async {
    var path = '/stats';
    if (year != null && month != null) {
      path = '/stats?year=$year&month=$month';
    } else if (year != null) {
      path = '/stats?year=$year';
    } else if (month != null) {
      path = '/stats?month=$month';
    }
    final response = await _get(path);
    return StatsResponse.fromJson(response);
  }

  Future<List<SearchResult>> search(
    String query, {
    String filter = 'all',
  }) async {
    if (query.trim().isEmpty) {
      return <SearchResult>[];
    }
    final encoded = Uri.encodeComponent(query);
    final path = '/library/search?query=$encoded&limit=50';
    final response = await _getList(path);
    return response
        .map((item) => SearchResult.fromJson(item))
        .where((item) => filter == 'all' ? true : item.kind == filter)
        .toList();
  }

  Future<Album> fetchAlbumById(String albumId) async {
    final encoded = _encodePathSegment(albumId);
    final response = await _get('/library/albums/$encoded');
    return Album.fromJson(response);
  }

  Future<Artist> fetchArtistById(String artistId) async {
    final encoded = _encodePathSegment(artistId);
    final response = await _get('/browse/artists/$encoded');
    return Artist.fromJson(response);
  }

  Future<Track> fetchTrackById(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    final response = await _get('/browse/tracks/$encoded');
    return Track.fromJson(response);
  }

  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    final response = await _get('/library/tracks/$encoded/offline-metadata');
    return OfflineTrackMetadata.fromJson(response);
  }

  Future<DownloadBatchManifest> createDownloadBatch(
    List<String> trackIds, {
    String? clientBatchId,
  }) async {
    final payload = <String, dynamic>{
      'track_ids': trackIds,
      if (clientBatchId != null && clientBatchId.trim().isNotEmpty)
        'client_batch_id': clientBatchId.trim(),
    };
    final response = await _post('/download/batches', payload);
    return DownloadBatchManifest.fromJson(response);
  }

  Future<ServerCapabilities> fetchCapabilities() async {
    final response = await _get(
      '/server/capabilities',
      timeout: _healthRequestTimeout,
      retryable: false,
    );
    return ServerCapabilities.fromJson(response);
  }

  Future<DownloadJobV2> createDownloadJob({
    required String clientId,
    required String clientRequestId,
    required DownloadJobScopeV2 scope,
  }) async {
    final response = await _post('/download/v2/jobs', {
      'client_id': clientId,
      'client_request_id': clientRequestId,
      'scope': scope.toJson(),
    });
    return DownloadJobV2.fromJson(response);
  }

  Future<List<DownloadJobV2>> fetchDownloadJobs({
    String? clientId,
    String? scopeKind,
    String? scopeId,
  }) async {
    final query = <String, String>{
      if (clientId != null && clientId.trim().isNotEmpty)
        'client_id': clientId.trim(),
      if (scopeKind != null && scopeKind.trim().isNotEmpty)
        'scope_kind': scopeKind.trim(),
      if (scopeId != null && scopeId.trim().isNotEmpty)
        'scope_id': scopeId.trim(),
    };
    final suffix = query.isEmpty
        ? ''
        : '?${query.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
    final response = await _getList('/download/v2/jobs$suffix');
    return response.map((item) => DownloadJobV2.fromJson(item)).toList();
  }

  Future<void> applyDownloadJobAction({
    required String jobId,
    required String action,
  }) async {
    final encoded = _encodePathSegment(jobId);
    await _postVoid('/download/v2/jobs/$encoded/actions', {'action': action});
  }

  Future<List<TrackMatchResult>> matchTracks(
    List<TrackMatchDescriptor> tracks,
  ) async {
    if (tracks.isEmpty) {
      return const <TrackMatchResult>[];
    }
    final response = await _post('/library/match-tracks', {
      'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
    });
    final rawMatches = response['matches'];
    if (rawMatches is! List) {
      return const <TrackMatchResult>[];
    }
    return rawMatches
        .whereType<Map>()
        .map(
          (item) => TrackMatchResult.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (item) =>
              item.localTrackId.trim().isNotEmpty &&
              item.serverTrackId.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<void> likeTrack(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    await _postVoid('/library/likes/$encoded', {});
  }

  Future<void> unlikeTrack(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    await _delete('/library/likes/$encoded');
  }

  Future<List<ServerLikeState>> updateLikeStates(
    Map<String, bool> states, {
    Map<String, int> updatedAtByTrack = const <String, int>{},
  }) async {
    if (states.isEmpty) {
      return const <ServerLikeState>[];
    }
    final response = await _postList('/library/likes/batch', {
      'items': states.entries
          .map((entry) {
            final updatedAt = updatedAtByTrack[entry.key];
            return {
              'track_id': entry.key,
              'liked': entry.value,
              if (updatedAt != null && updatedAt > 0) 'updated_at': updatedAt,
            };
          })
          .toList(growable: false),
    });
    return response
        .map((item) => ServerLikeState.fromJson(item))
        .where((item) => item.trackId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<ServerLikeState?> setLikeState(String trackId, bool liked) async {
    final states = await updateLikeStates({trackId: liked});
    return states.isEmpty ? null : states.first;
  }

  Future<Playlist> createPlaylist(String name, {String? description}) async {
    final response = await _post('/library/playlists', {
      'name': name,
      'description': description?.trim() ?? '',
    });
    return Playlist.fromJson(response);
  }

  Future<Playlist> renamePlaylist(
    String playlistId,
    String name, {
    String? description,
  }) async {
    final encoded = _encodePathSegment(playlistId);
    final response = await _post('/library/playlists/$encoded', {
      'name': name,
      'description': description?.trim() ?? '',
    });
    return Playlist.fromJson(response);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final encoded = _encodePathSegment(playlistId);
    await _delete('/library/playlists/$encoded');
  }

  String buildPlaylistCoverUrl(String playlistId, {String? imageRef}) {
    final encoded = _encodePathSegment(playlistId);
    var url = '$_baseUrl/library/playlists/$encoded/cover';
    final ref = imageRef?.trim();
    if (ref != null && ref.isNotEmpty) {
      url = '$url?v=${Uri.encodeComponent(ref)}';
    }
    return url;
  }

  Future<Playlist> uploadPlaylistCover(
    String playlistId,
    List<int> bytes,
    String contentType,
  ) async {
    final encoded = _encodePathSegment(playlistId);
    final response = await _executeRequest(
      () => _client.put(
        Uri.parse('$_baseUrl/library/playlists/$encoded/cover'),
        headers: _headers(contentTypeValue: contentType),
        body: bytes,
      ),
      label: 'PUT playlist cover',
    );
    return Playlist.fromJson(await _decode(response));
  }

  Future<Playlist> deletePlaylistCover(String playlistId) async {
    final encoded = _encodePathSegment(playlistId);
    final response = await _executeRequest(
      () => _client.delete(
        Uri.parse('$_baseUrl/library/playlists/$encoded/cover'),
        headers: _headers(),
      ),
      label: 'DELETE playlist cover',
    );
    return Playlist.fromJson(await _decode(response));
  }

  Future<Playlist> updatePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    final encoded = _encodePathSegment(playlistId);
    final response = await _post('/library/playlists/$encoded', {
      'track_ids': trackIds,
    });
    return Playlist.fromJson(response);
  }

  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = _defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _get(
      '/player/settings',
      timeout: timeout,
      retryable: retryable,
    );
    return PlaybackSettingsResponse.fromJson(response);
  }

  Future<void> updatePlaybackSettings({required String repeatMode}) async {
    await _postVoid('/player/settings', {'repeat_mode': repeatMode});
  }

  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = _defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _get(
      '/server/ports',
      timeout: timeout,
      retryable: retryable,
    );
    return ServerPortsResponse.fromJson(response);
  }

  Stream<MetadataUpdateEvent> streamMetadataEvents() async* {
    final request = http.Request(
      'GET',
      Uri.parse('$_baseUrl/library/metadata-events'),
    );
    request.headers.addAll(_headers());
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer = (buffer + chunk).replaceAll('\r\n', '\n');
      var separator = buffer.indexOf('\n\n');
      while (separator >= 0) {
        final frame = buffer.substring(0, separator);
        buffer = buffer.substring(separator + 2);
        final event = _metadataEventFromSseFrame(frame);
        if (event != null) {
          yield event;
        }
        separator = buffer.indexOf('\n\n');
      }
    }

    final trailingFrame = buffer.trim();
    if (trailingFrame.isNotEmpty) {
      final event = _metadataEventFromSseFrame(trailingFrame);
      if (event != null) {
        yield event;
      }
    }
  }

  String buildAlbumCoverUrl(String albumId) {
    final encoded = _encodePathSegment(albumId);
    return '$_baseUrl/library/albums/$encoded/cover';
  }

  String buildArtistCoverUrl(String artistId, {String? kind}) {
    final encoded = _encodePathSegment(artistId);
    var path = '/library/artists/$encoded/cover';
    if (kind != null && kind.isNotEmpty) {
      path = '$path?kind=${Uri.encodeComponent(kind)}';
    }
    return '$_baseUrl$path';
  }

  Future<ServerArtwork?> fetchAlbumCoverBytes(
    String albumId, {
    Duration timeout = _defaultRequestTimeout,
  }) {
    return _fetchArtworkUrl(buildAlbumCoverUrl(albumId), timeout: timeout);
  }

  Future<ServerArtwork?> fetchArtistCoverBytes(
    String artistId, {
    String kind = 'logo',
    Duration timeout = _defaultRequestTimeout,
  }) {
    return _fetchArtworkUrl(
      buildArtistCoverUrl(artistId, kind: kind),
      timeout: timeout,
    );
  }

  String buildTrackDownloadUrl(String trackId) {
    final encoded = _encodePathSegment(trackId);
    return '$_baseUrl/download/tracks/$encoded';
  }

  String buildDownloadUrl(String trackId, {String? downloadUrl}) {
    final value = downloadUrl?.trim();
    if (value == null || value.isEmpty) {
      return buildTrackDownloadUrl(trackId);
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/api/')) {
      final root = _ensureRoot(_baseUrl);
      return '${root.endsWith('/') ? root.substring(0, root.length - 1) : root}$value';
    }
    if (value.startsWith('/')) {
      return '$_baseUrl$value';
    }
    return '$_baseUrl/$value';
  }

  Future<TrackDownloadStream> openTrackDownload(
    String trackId, {
    int? startByte,
    String? ifRange,
    Duration timeout = _defaultRequestTimeout,
  }) async {
    final request = http.Request(
      'GET',
      Uri.parse(buildTrackDownloadUrl(trackId)),
    );
    request.headers.addAll(_headers());
    if (startByte != null && startByte > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$startByte-';
      if (ifRange != null && ifRange.trim().isNotEmpty) {
        request.headers[HttpHeaders.ifRangeHeader] = ifRange.trim();
      }
    }

    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200 && response.statusCode != 206) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    return TrackDownloadStream(
      statusCode: response.statusCode,
      stream: response.stream,
      contentLength:
          response.contentLength == null || response.contentLength! < 0
          ? null
          : response.contentLength,
      contentRange: response.headers[HttpHeaders.contentRangeHeader],
      contentType: response.headers[HttpHeaders.contentTypeHeader],
      contentDisposition: response.headers['content-disposition'],
      etag: response.headers[HttpHeaders.etagHeader],
      sha256: response.headers['x-phonolite-sha256'],
    );
  }

  Future<ServerArtwork?> _fetchArtworkUrl(
    String url, {
    required Duration timeout,
  }) async {
    final response = await _executeRequest(
      () => _client.get(Uri.parse(url), headers: _headers()),
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
    return ServerArtwork(
      bytes: response.bodyBytes,
      contentType: response.headers[HttpHeaders.contentTypeHeader],
    );
  }

  String _ensureApiBase(String url) {
    final uri = Uri.parse(url);
    var path = uri.path;
    if (path.isEmpty || path == '/') {
      path = '/api/v1';
    } else if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (!path.endsWith('/api/v1')) {
      path = '$path/api/v1';
    }
    return uri.replace(path: path, query: null).toString();
  }

  String _ensureRoot(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    var path = uri.path;
    if (path.endsWith('/api/v1')) {
      path = path.substring(0, path.length - '/api/v1'.length);
      if (path.isEmpty) {
        path = '/';
      }
    }
    return uri.replace(path: path, query: null).toString();
  }

  static String _sanitizeInput(String input) {
    var value = input.trim();
    while (value.endsWith('?') || value.endsWith('#')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _sanitizeBaseUrl(String input) {
    final cleaned = _sanitizeInput(input);
    return cleaned.replaceAll(RegExp(r'/+$'), '');
  }

  static String _encodePathSegment(String value) {
    return Uri.encodeComponent(value);
  }

  Future<bool> _checkHealth(String url) async {
    final healthUrl = Uri.parse('$url/health');
    try {
      final response = await _client
          .get(healthUrl)
          .timeout(_healthRequestTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<int?> pingHealthMs({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final rootUrl = _ensureRoot(_baseUrl);
    final healthUrl = Uri.parse('$rootUrl/health');
    final start = DateTime.now();
    try {
      final response = await _client.get(healthUrl).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return DateTime.now().difference(start).inMilliseconds;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = _defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _executeRequest(
      () => _client.get(Uri.parse('$_baseUrl$path'), headers: _headers()),
      label: 'GET $path',
      retryable: retryable,
      timeout: timeout,
    );
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Duration timeout = _defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final response = await _executeRequest(
      () => _client.get(Uri.parse('$_baseUrl$path'), headers: _headers()),
      label: 'GET $path',
      retryable: retryable,
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final decoded = await _decodeJson(response.body);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Expected list response for $path');
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: jsonEncode(payload),
      ),
      label: 'POST $path',
    );
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> _postList(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: jsonEncode(payload),
      ),
      label: 'POST $path',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final decoded = await _decodeJson(response.body);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Expected list response for $path');
  }

  Future<void> _postVoid(String path, Map<String, dynamic> payload) async {
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: jsonEncode(payload),
      ),
      label: 'POST $path',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<void> _delete(String path) async {
    final response = await _executeRequest(
      () => _client.delete(Uri.parse('$_baseUrl$path'), headers: _headers()),
      label: 'DELETE $path',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> _headers({
    bool contentType = false,
    String? contentTypeValue,
  }) {
    final headers = <String, String>{};
    if (contentTypeValue != null && contentTypeValue.isNotEmpty) {
      headers['Content-Type'] = contentTypeValue;
    } else if (contentType) {
      headers['Content-Type'] = 'application/json';
    }
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<http.Response> _executeRequest(
    Future<http.Response> Function() request, {
    bool retryable = false,
    Duration timeout = _defaultRequestTimeout,
    String label = 'request',
  }) async {
    final maxAttempts = retryable ? _maxGetAttempts : 1;
    Object? lastError;
    StackTrace? lastStackTrace;
    final stopwatch = Stopwatch()..start();

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await request().timeout(timeout);
        final retryableStatus =
            response.statusCode >= 500 && response.statusCode < 600;
        if (retryable && retryableStatus && attempt < maxAttempts) {
          developer.log(
            '$label attempt $attempt failed with ${response.statusCode}; retrying after ${stopwatch.elapsedMilliseconds}ms',
            name: 'ServerConnection',
          );
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
        if (attempt > 1 || stopwatch.elapsed >= _slowRequestThreshold) {
          developer.log(
            '$label completed in ${stopwatch.elapsedMilliseconds}ms after $attempt attempt(s) with ${response.statusCode}',
            name: 'ServerConnection',
          );
        }
        return response;
      } on TimeoutException catch (_, stackTrace) {
        lastError = RequestTimeoutException(timeout);
        lastStackTrace = stackTrace;
        if (attempt < maxAttempts) {
          developer.log(
            '$label attempt $attempt timed out after ${timeout.inMilliseconds}ms; retrying',
            name: 'ServerConnection',
          );
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
      } on SocketException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;
        if (retryable && attempt < maxAttempts) {
          developer.log(
            '$label attempt $attempt hit socket error "$err"; retrying',
            name: 'ServerConnection',
          );
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
      } on http.ClientException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;
        if (retryable && attempt < maxAttempts) {
          developer.log(
            '$label attempt $attempt hit client error "$err"; retrying',
            name: 'ServerConnection',
          );
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
      }
    }

    if (lastError != null && lastStackTrace != null) {
      developer.log(
        '$label failed after ${stopwatch.elapsedMilliseconds}ms',
        name: 'ServerConnection',
        error: lastError,
        stackTrace: lastStackTrace,
      );
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw RequestTimeoutException(timeout);
  }

  Duration _retryDelay(int attempt) {
    final baseMs = attempt == 1 ? 300 : 900;
    return Duration(milliseconds: baseMs + _retryJitter.nextInt(250));
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = await _decodeJson(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected response payload');
  }
}

MetadataUpdateEvent? _metadataEventFromSseFrame(String frame) {
  final data = <String>[];
  for (final rawLine in frame.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  if (data.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(data.join('\n'));
    if (decoded is Map<String, dynamic>) {
      final event = MetadataUpdateEvent.fromJson(decoded);
      if (event.kind.isNotEmpty && event.id.isNotEmpty) {
        return event;
      }
    }
  } catch (err, stackTrace) {
    developer.log(
      'Ignoring malformed metadata event',
      name: 'ServerConnection',
      error: err,
      stackTrace: stackTrace,
    );
  }
  return null;
}

Future<dynamic> _decodeJson(String body) {
  if (body.length < 64 * 1024) {
    return Future<dynamic>.value(jsonDecode(body));
  }
  return Isolate.run<dynamic>(() => jsonDecode(body));
}

class PlaybackSettingsResponse {
  PlaybackSettingsResponse({required this.repeatMode});

  final String repeatMode;

  factory PlaybackSettingsResponse.fromJson(Map<String, dynamic> json) {
    return PlaybackSettingsResponse(
      repeatMode: json['repeat_mode'] as String? ?? 'off',
    );
  }
}

class ServerPortsResponse {
  ServerPortsResponse({
    required this.httpPort,
    required this.quicPort,
    required this.quicEnabled,
  });

  final int? httpPort;
  final int? quicPort;
  final bool quicEnabled;

  factory ServerPortsResponse.fromJson(Map<String, dynamic> json) {
    return ServerPortsResponse(
      httpPort: (json['http_port'] as num?)?.toInt(),
      quicPort: (json['quic_port'] as num?)?.toInt(),
      quicEnabled: json['quic_enabled'] == true,
    );
  }
}
