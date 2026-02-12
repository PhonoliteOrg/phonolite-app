import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ServerConnection {
  ServerConnection({required String baseUrl, http.Client? client})
      : _baseUrl = _sanitizeBaseUrl(baseUrl),
        _client = client ?? http.Client();

  String _baseUrl;
  final http.Client _client;
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
    final hasScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://');
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

  Future<String> login({required String username, required String password}) async {
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

  Future<List<Artist>> fetchArtists() async {
    const limit = 200;
    var offset = 0;
    final artists = <Artist>[];
    while (true) {
      final response = await _getList('/browse/artists?limit=$limit&offset=$offset');
      artists.addAll(response.map((item) => Artist.fromJson(item)));
      if (response.length < limit) {
        break;
      }
      offset += response.length;
    }
    return artists;
  }

  Future<List<Album>> fetchAlbums(String artistId) async {
    final response = await _getList('/browse/artists/$artistId/albums');
    return response.map((item) => Album.fromJson(item)).toList();
  }

  Future<List<Track>> fetchTracks(String albumId) async {
    final response = await _getList('/browse/albums/$albumId/tracks');
    return response.map((item) => Track.fromJson(item)).toList();
  }

  Future<List<Playlist>> fetchPlaylists() async {
    final response = await _getList('/library/playlists');
    return response.map((item) => Playlist.fromJson(item)).toList();
  }

  Future<List<Track>> fetchPlaylistTracks(String playlistId) async {
    final response = await _getList('/browse/playlists/$playlistId/tracks');
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

  Future<List<SearchResult>> search(String query, {String filter = 'all'}) async {
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
    final response = await _get('/library/albums/$albumId');
    return Album.fromJson(response);
  }

  Future<Artist> fetchArtistById(String artistId) async {
    final response = await _get('/browse/artists/$artistId');
    return Artist.fromJson(response);
  }

  Future<Track> fetchTrackById(String trackId) async {
    final response = await _get('/browse/tracks/$trackId');
    return Track.fromJson(response);
  }

  Future<void> likeTrack(String trackId) async {
    await _postVoid('/library/likes/$trackId', {});
  }

  Future<void> unlikeTrack(String trackId) async {
    await _delete('/library/likes/$trackId');
  }

  Future<Playlist> createPlaylist(String name) async {
    final response = await _post('/library/playlists', {'name': name});
    return Playlist.fromJson(response);
  }

  Future<Playlist> renamePlaylist(String playlistId, String name) async {
    final response = await _post('/library/playlists/$playlistId', {'name': name});
    return Playlist.fromJson(response);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _delete('/library/playlists/$playlistId');
  }

  Future<Playlist> updatePlaylistTracks(String playlistId, List<String> trackIds) async {
    final response = await _post('/library/playlists/$playlistId', {
      'track_ids': trackIds,
    });
    return Playlist.fromJson(response);
  }

  Future<PlayerQueueResponse> queueAlbum(String albumId, {String? startTrackId}) async {
    var path = '/player/queue/album/$albumId';
    if (startTrackId != null) {
      path = '$path?start=$startTrackId';
    }
    final response = await _post(path, {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<PlayerQueueResponse> queuePlaylist(String playlistId, {String? startTrackId}) async {
    var path = '/player/queue/playlist/$playlistId';
    if (startTrackId != null) {
      path = '$path?start=$startTrackId';
    }
    final response = await _post(path, {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<PlayerQueueResponse> queueLiked({String? startTrackId}) async {
    var path = '/player/queue/liked';
    if (startTrackId != null) {
      path = '$path?start=$startTrackId';
    }
    final response = await _post(path, {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<PlayerQueueResponse> queueShuffle({
    required String mode,
    required String scope,
    String? playlistId,
  }) async {
    var path = '/player/queue/shuffle?mode=$mode&scope=$scope';
    if (playlistId != null) {
      path = '$path&playlist_id=$playlistId';
    }
    final response = await _post(path, {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<PlayerQueueResponse> nextTrack() async {
    final response = await _post('/player/queue/next', {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<PlayerQueueResponse> prevTrack() async {
    final response = await _post('/player/queue/prev', {});
    return PlayerQueueResponse.fromJson(response);
  }

  Future<void> stopPlayback() async {
    await _postVoid('/player/stop', {});
  }

  Future<void> pausePlayback(bool paused) async {
    await _postVoid('/player/pause', {'paused': paused});
  }

  Future<PlaybackSettingsResponse> fetchPlaybackSettings() async {
    final response = await _get('/player/settings');
    return PlaybackSettingsResponse.fromJson(response);
  }

  Future<void> updatePlaybackSettings({required String repeatMode}) async {
    await _postVoid('/player/settings', {'repeat_mode': repeatMode});
  }

  Future<ServerPortsResponse> fetchServerPorts() async {
    final response = await _get('/server/ports');
    return ServerPortsResponse.fromJson(response);
  }

  String buildAlbumCoverUrl(String albumId) {
    final encoded = Uri.encodeComponent(albumId);
    return '$_baseUrl/library/albums/$encoded/cover';
  }

  String buildArtistCoverUrl(String artistId, {String? kind}) {
    final encoded = Uri.encodeComponent(artistId);
    var path = '/library/artists/$encoded/cover';
    if (kind != null && kind.isNotEmpty) {
      path = '$path?kind=${Uri.encodeComponent(kind)}';
    }
    return '$_baseUrl$path';
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
    return uri.replace(path: path, query: '').toString();
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
    return uri.replace(path: path, query: '').toString();
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

  Future<bool> _checkHealth(String url) async {
    final healthUrl = Uri.parse('$url/health');
    try {
      final response = await _client.get(healthUrl);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<int?> pingHealthMs({Duration timeout = const Duration(seconds: 3)}) async {
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


  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    if (decoded is Map && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }
    throw Exception('Expected list response for $path');
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(contentType: true),
      body: jsonEncode(payload),
    );
    return _decode(response);
  }

  Future<void> _postVoid(String path, Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(contentType: true),
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<void> _delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Map<String, String> _headers({bool contentType = false}) {
    final headers = <String, String>{};
    if (contentType) {
      headers['Content-Type'] = 'application/json';
    }
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected response payload');
  }
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
