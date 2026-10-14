import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:phonolite_quic/phonolite_quic.dart';

import 'models.dart';
import 'server_trust.dart';

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

class ServerConnectionCheckException implements Exception {
  ServerConnectionCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ServerReachabilityProbe =
    Future<void> Function({
      required String host,
      required int port,
      String? expectedSpki,
    });

/// Safe to display without exposing passwords, bearer tokens, or response data.
class PasswordChangeException implements Exception {
  PasswordChangeException(
    this.message, {
    this.requiresSignIn = false,
    this.statusCode,
  });

  final String message;
  final bool requiresSignIn;
  final int? statusCode;

  @override
  String toString() => message;
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

  ServerConnection({
    required String baseUrl,
    http.Client? client,
    ServerReachabilityProbe? serverProbe,
  }) : _baseUrl = _sanitizeBaseUrl(baseUrl),
       _serverProbe = serverProbe ?? probeServerConnection,
       _injectedClient = client != null {
    _client = client ?? pinnedApiClient(() => _baseUrl);
  }

  String _baseUrl;
  late final http.Client _client;
  final bool _injectedClient;
  final ServerReachabilityProbe _serverProbe;
  final Random _retryJitter = Random();
  final Map<String, Future<Map<String, dynamic>>> _metadataRequests = {};
  int _sessionRevision = 0;
  String? _token;
  void Function(Object error)? onTransportFailure;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  ServerTrust? get trust => ServerTrustRegistry.lookup(_baseUrl);
  bool get hasTrustedTransport => _injectedClient || trust != null;
  void setTrust(ServerTrust value) =>
      ServerTrustRegistry.register(_baseUrl, value);
  int get sessionRevision => _sessionRevision;

  bool get canChangeOwnPassword {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.path != '/api/v1' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final authenticatedTrust = trust;
    return _token?.isNotEmpty == true &&
        authenticatedTrust != null &&
        ServerTrust.fromJson(authenticatedTrust.toJson()) != null;
  }

  /// A fresh header map; callers cannot mutate connection authentication state.
  Map<String, String> get authorizationHeaders => {
    if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  void setBaseUrl(String baseUrl) {
    final sanitized = _sanitizeBaseUrl(baseUrl);
    if (_baseUrl == sanitized) {
      return;
    }
    _baseUrl = sanitized;
    _token = null;
    _invalidateMetadataRequests();
  }

  Future<String> resolveBaseUrl(String input) async {
    final trimmed = _sanitizeInput(input);
    if (trimmed.isEmpty) {
      throw Exception('Server URL is required');
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/' && uri.path != '/api/v1')) {
      throw Exception('Enter the server IP and HTTPS port');
    }
    return _ensureApiBase(candidate);
  }

  /// Verify the entered endpoint without changing the session or trusting a new
  /// identity. A remembered certificate pin is enforced even before sign-in.
  Future<void> verifyServerConnection(
    String input, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final resolved = await resolveBaseUrl(input);
    final uri = Uri.parse(resolved);
    try {
      await (() async {
        final existing =
            ServerTrustRegistry.lookup(resolved) ??
            await ServerTrustStore.read(resolved);
        await _serverProbe(
          host: uri.host,
          port: uri.port,
          expectedSpki: existing?.spki,
        );
      })().timeout(timeout);
    } on TimeoutException {
      throw ServerConnectionCheckException(
        'Connection timed out. Check the server address and port.',
      );
    } on QuicException catch (error) {
      throw ServerConnectionCheckException(error.message);
    }
  }

  void setToken(String? token) {
    if (token != null && token.isNotEmpty && !hasTrustedTransport) {
      throw StateError('Authenticate the server before using a saved token');
    }
    if (_token == token) {
      return;
    }
    _token = token;
    _invalidateMetadataRequests();
  }

  void _invalidateMetadataRequests() {
    _sessionRevision++;
    invalidateMetadataReads();
  }

  /// A metadata event supersedes reads that began before that update, without
  /// changing the authenticated session or cancelling unrelated repair work.
  void invalidateMetadataReads() {
    _metadataRequests.clear();
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final url = _baseUrl;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.path != '/api/v1' ||
        uri.userInfo.isNotEmpty) {
      throw StateError('HTTPS /api/v1 is required');
    }
    setToken(null);
    final revision = _sessionRevision;
    final existing = trust ?? await ServerTrustStore.read(url);
    final response = await authenticateServer(
      host: uri.host,
      port: uri.port,
      username: username,
      password: password,
      expectedSpki: existing?.spki,
      expectedOpaque: existing?.opaqueKey,
    );
    if (_baseUrl != url || _sessionRevision != revision) {
      throw StateError('Sign-in cancelled');
    }
    final authenticated = ServerTrust(
      spki: response['spki_sha256'] as String,
      opaqueKey: response['opaque_key'] as String,
    );
    await ServerTrustStore.write(url, authenticated);
    if (_baseUrl != url || _sessionRevision != revision) {
      throw StateError('Sign-in cancelled');
    }
    setTrust(authenticated);
    final token = response['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Missing token in login response');
    }
    setToken(token);
    return token;
  }

  Future<void> logout({Duration timeout = _defaultRequestTimeout}) async {
    await _postVoid('/auth/logout', {}, timeout: timeout);
  }

  /// Changes only the authenticated user's password over the pinned HTTPS
  /// connection. This mutation is never retried or redirected. The controller
  /// keeps the originating session signed in; other account sessions are revoked.
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
    Duration timeout = _defaultRequestTimeout,
  }) async {
    if (!canChangeOwnPassword) {
      throw PasswordChangeException(
        'Connect to your authenticated server before resetting your password.',
      );
    }
    if (currentPassword.isEmpty || utf8.encode(currentPassword).length > 1024) {
      throw PasswordChangeException('Enter your current password.');
    }
    if (newPassword.isEmpty) {
      throw PasswordChangeException('Enter your new password.');
    }
    if (utf8.encode(newPassword).length > 1024) {
      throw PasswordChangeException('Your new password is too long.');
    }
    final url = _baseUrl;
    final token = _token;
    final revision = _sessionRevision;
    final pin = trust!;
    bool sessionIsCurrent() =>
        _baseUrl == url &&
        _token == token &&
        _sessionRevision == revision &&
        trust?.spki == pin.spki &&
        trust?.opaqueKey == pin.opaqueKey;
    final request = http.Request('POST', Uri.parse('$url/auth/password'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      })
      ..body = jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    late final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } catch (_) {
      if (!sessionIsCurrent()) {
        throw PasswordChangeException(
          'Your server session changed. Return to settings before resetting your password.',
        );
      }
      // The server may have committed the change before the response was lost.
      // Do not retry or log the raw transport error. The server preserves this
      // session even if the change committed before the response was lost.
      throw PasswordChangeException(
        'The password change could not be confirmed. Check your connection and password before trying again.',
      );
    }
    // No endpoint response data is needed, even when the server returns an
    // error. Cancel rather than retaining or displaying an arbitrary body.
    unawaited(
      response.stream
          .listen((_) {}, onError: (Object _) {})
          .cancel()
          .catchError((Object _) {}),
    );
    if (!sessionIsCurrent()) {
      throw PasswordChangeException(
        'Your server session changed. Return to settings before resetting your password.',
      );
    }
    if (response.statusCode == 204) return;
    final message = switch (response.statusCode) {
      400 => 'The server rejected the password change.',
      401 =>
        'Your session has expired. Sign in again before resetting your password.',
      403 => 'Your current password is incorrect.',
      429 =>
        'Too many password reset attempts. Wait a few minutes and try again.',
      _ =>
        'The password change could not be confirmed. Check your connection and password before trying again.',
    };
    throw PasswordChangeException(
      message,
      statusCode: response.statusCode,
      requiresSignIn: response.statusCode == 401,
    );
  }

  Future<List<Artist>> fetchArtistsPage({
    int limit = ServerConnection.artistsPageSize,
    int offset = 0,
    bool includeContributors = false,
  }) async {
    final response = await _getList(
      '/browse/artists?limit=$limit&offset=$offset&include_contributors=$includeContributors',
    );
    return response.map((item) => Artist.fromJson(item)).toList();
  }

  Future<List<Artist>> fetchArtists({
    int limit = ServerConnection.artistsPageSize,
    bool includeContributors = false,
  }) async {
    var offset = 0;
    final artists = <Artist>[];
    while (true) {
      final page = await fetchArtistsPage(
        limit: limit,
        offset: offset,
        includeContributors: includeContributors,
      );
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

  Future<ArtistReleases> fetchArtistReleases(String artistId) async {
    final encoded = _encodePathSegment(artistId);
    final response = await _get('/browse/artists/$encoded/releases');
    return ArtistReleases.fromJson(response);
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

  /// Legacy migration queue only; new listening uses the v2 counter endpoints.
  Future<Map<String, dynamic>> fetchListeningChanges({
    required String deviceId,
    int after = 0,
    int limit = 200,
  }) => _get(
    '/stats/sync?device_id=${Uri.encodeQueryComponent(deviceId)}&after=$after&limit=$limit',
    retryable: false,
  );

  Future<Map<String, dynamic>> updateListeningPreference({
    required String deviceId,
    required bool enabled,
    required int revision,
  }) => _post('/stats/preferences', {
    'device_id': deviceId,
    'enabled': enabled,
    'revision': revision,
  });

  Future<Map<String, dynamic>> uploadListeningEvents({
    required String deviceId,
    required int historyGeneration,
    required List<Map<String, dynamic>> events,
  }) => _post('/stats/events', {
    'device_id': deviceId,
    'history_generation': historyGeneration,
    'events': events,
  });

  Future<Map<String, dynamic>> resetListeningHistory({
    required int historyGeneration,
  }) => _post('/stats/reset', {'history_generation': historyGeneration});

  Future<Map<String, dynamic>> fetchListeningCounterState({
    required String deviceId,
  }) => _get(
    '/stats/v2/state?device_id=${Uri.encodeQueryComponent(deviceId)}',
    retryable: false,
  );

  Future<Map<String, dynamic>> activateListeningCounters({
    required String deviceId,
    required int historyGeneration,
  }) => _post('/stats/v2/activate', {
    'device_id': deviceId,
    'history_generation': historyGeneration,
  });

  Future<Map<String, dynamic>> uploadListeningCounters(
    Map<String, dynamic> batch,
  ) => _post('/stats/v2/batch', batch);

  Future<Map<String, dynamic>> fetchListeningCounterSnapshot({
    required String deviceId,
    required int year,
    required int month,
    int? revision,
    String after = '',
  }) => _get(
    '/stats/v2/snapshot?device_id=${Uri.encodeQueryComponent(deviceId)}&year=$year&month=$month'
    '&after=${Uri.encodeQueryComponent(after)}${revision == null ? '' : '&revision=$revision'}',
    retryable: false,
  );

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
    final response = await _getMetadata('/library/albums/$encoded');
    return Album.fromJson(response);
  }

  Future<Artist> fetchArtistById(String artistId) async {
    final encoded = _encodePathSegment(artistId);
    final response = await _getMetadata('/browse/artists/$encoded');
    return Artist.fromJson(response);
  }

  Future<Track> fetchTrackById(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    final response = await _getMetadata('/browse/tracks/$encoded');
    return Track.fromJson(response);
  }

  Future<OfflineTrackMetadata> fetchOfflineMetadata(String trackId) async {
    final encoded = _encodePathSegment(trackId);
    final response = await _getMetadata(
      '/library/tracks/$encoded/offline-metadata',
    );
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

  String buildArtistCoverUrl(String artistId, {String? kind, String? ref}) {
    final encoded = _encodePathSegment(artistId);
    var path = '/library/artists/$encoded/cover';
    if (kind != null && kind.isNotEmpty) {
      path = '$path?kind=${Uri.encodeComponent(kind)}';
    }
    if (ref != null && ref.trim().isNotEmpty) {
      path =
          '$path${path.contains('?') ? '&' : '?'}v=${Uri.encodeComponent(ref)}';
    }
    return '$_baseUrl$path';
  }

  Future<ServerArtwork?> fetchAlbumCoverBytes(
    String albumId, {
    Duration timeout = _defaultRequestTimeout,
  }) {
    return _fetchArtworkUrl(buildAlbumCoverUrl(albumId), timeout: timeout);
  }

  Future<ServerArtwork?> fetchPlaylistCoverBytes(
    String playlistId, {
    String? imageRef,
    Duration timeout = _defaultRequestTimeout,
  }) {
    return _fetchArtworkUrl(
      buildPlaylistCoverUrl(playlistId, imageRef: imageRef),
      timeout: timeout,
    );
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

  Future<int?> _probeHealthMs(String url, {required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client.get(_buildHealthUrl(url)).timeout(timeout);
      final success = response.statusCode >= 200 && response.statusCode < 300;
      return success ? stopwatch.elapsedMilliseconds : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> pingHealthMs({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    for (final url in _healthProbeBaseUrls(_baseUrl)) {
      final elapsedMs = await _probeHealthMs(url, timeout: timeout);
      if (elapsedMs != null) return elapsedMs;
    }
    return null;
  }

  Iterable<String> _healthProbeBaseUrls(String baseUrl) sync* {
    final rootUrl = _ensureRoot(baseUrl);
    yield rootUrl;
    if (rootUrl != baseUrl) {
      yield baseUrl;
    }
  }

  Uri _buildHealthUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(
      path: path.isEmpty ? '/health' : '$path/health',
      query: null,
    );
  }

  // Only coalesce reads that overlap. Completed metadata is never cached;
  // metadata events invalidate pending reads before requesting fresh data.
  Future<Map<String, dynamic>> _getMetadata(String path) {
    final existing = _metadataRequests[path];
    if (existing != null) {
      return existing;
    }
    late final Future<Map<String, dynamic>> pending;
    void removePending() {
      if (identical(_metadataRequests[path], pending)) {
        _metadataRequests.remove(path);
      }
    }

    pending = _get(path).then(
      (response) {
        removePending();
        return response;
      },
      onError: (Object error, StackTrace stackTrace) {
        removePending();
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _metadataRequests[path] = pending;
    return pending;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = _defaultRequestTimeout,
    bool retryable = true,
  }) async {
    // Retried reads belong to the server and credentials that started them.
    final uri = Uri.parse('$_baseUrl$path');
    final headers = _headers();
    final response = await _executeRequest(
      () => _client.get(uri, headers: headers),
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
    final body = jsonEncode(payload);
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: body,
      ),
      label: 'POST $path',
    );
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> _postList(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final body = jsonEncode(payload);
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: body,
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

  Future<void> _postVoid(
    String path,
    Map<String, dynamic> payload, {
    Duration timeout = _defaultRequestTimeout,
  }) async {
    final body = jsonEncode(payload);
    final response = await _executeRequest(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(contentType: true),
        body: body,
      ),
      label: 'POST $path',
      timeout: timeout,
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
    final headers = authorizationHeaders;
    if (contentTypeValue != null && contentTypeValue.isNotEmpty) {
      headers['Content-Type'] = contentTypeValue;
    } else if (contentType) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Future<http.Response> _executeRequest(
    Future<http.Response> Function() request, {
    bool retryable = false,
    Duration timeout = _defaultRequestTimeout,
    String label = 'request',
  }) async {
    final safeLabel = _safeRequestLabel(label);
    final maxAttempts = retryable ? _maxGetAttempts : 1;
    Object? lastError;
    StackTrace? lastStackTrace;
    final stopwatch = Stopwatch()..start();

    Future<void> backoff(int attempt) =>
        Future<void>.delayed(_retryDelay(attempt));

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await request().timeout(timeout);
        final retryableStatus =
            response.statusCode >= 500 && response.statusCode < 600;
        if (retryable && retryableStatus && attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt failed with ${response.statusCode}; retrying after ${stopwatch.elapsedMilliseconds}ms',
            name: 'ServerConnection',
          );
          await backoff(attempt);
          continue;
        }
        if (attempt > 1 || stopwatch.elapsed >= _slowRequestThreshold) {
          developer.log(
            '$safeLabel completed in ${stopwatch.elapsedMilliseconds}ms after $attempt attempt(s) with ${response.statusCode}',
            name: 'ServerConnection',
          );
        }
        return response;
      } on TimeoutException catch (_, stackTrace) {
        lastError = RequestTimeoutException(timeout);
        lastStackTrace = stackTrace;
        if (attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt timed out after ${timeout.inMilliseconds}ms; retrying',
            name: 'ServerConnection',
          );
          await backoff(attempt);
          continue;
        }
      } on SocketException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;
        if (retryable && attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt hit socket error; retrying',
            name: 'ServerConnection',
          );
          await backoff(attempt);
          continue;
        }
      } on http.ClientException catch (err, stackTrace) {
        lastError = err;
        lastStackTrace = stackTrace;
        if (retryable && attempt < maxAttempts) {
          developer.log(
            '$safeLabel attempt $attempt hit client error; retrying',
            name: 'ServerConnection',
          );
          await backoff(attempt);
          continue;
        }
      }
    }

    if (lastError != null && lastStackTrace != null) {
      try {
        onTransportFailure?.call(lastError);
      } catch (_) {}
      developer.log(
        '$safeLabel failed after ${stopwatch.elapsedMilliseconds}ms',
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

/// Keep only route templates. Never persist query values, resource IDs,
/// credentials, or a configured server address in request logs.
String _safeRequestLabel(String label) {
  if (label == 'GET artwork' ||
      label == 'PUT playlist cover' ||
      label == 'DELETE playlist cover') {
    return label;
  }
  final separator = label.indexOf(' ');
  if (separator < 0) return 'request';
  final method = label.substring(0, separator);
  if (!const ['GET', 'POST', 'PUT', 'DELETE'].contains(method)) {
    return 'request';
  }
  final path = label.substring(separator + 1).split('?').first;
  const staticRoutes = {
    '/auth/opaque/start',
    '/auth/opaque/finish',
    '/auth/logout',
    '/browse/artists',
    '/browse/likes',
    '/library/playlists',
    '/library/shuffle',
    '/library/search',
    '/library/match-tracks',
    '/library/likes/batch',
    '/stats',
    '/download/batches',
    '/download/v2/jobs',
    '/server/capabilities',
    '/server/ports',
    '/player/settings',
  };
  if (staticRoutes.contains(path)) return '$method $path';
  const dynamicRoutes = {
    '/browse/artists/:id/albums',
    '/browse/artists/:id/releases',
    '/browse/artists/:id',
    '/browse/albums/:id/tracks',
    '/browse/playlists/:id/tracks',
    '/browse/tracks/:id',
    '/library/albums/:id',
    '/library/tracks/:id/offline-metadata',
    '/library/likes/:id',
    '/library/playlists/:id',
    '/download/v2/jobs/:id/actions',
  };
  for (final route in dynamicRoutes) {
    final pattern = RegExp('^${route.replaceAll(':id', '[^/]+')}\$');
    if (pattern.hasMatch(path)) return '$method $route';
  }
  return '$method /unknown';
}

Future<dynamic> _decodeJson(String body) async {
  return body.length >= 64 * 1024
      ? await _decodeLargeJson(body)
      : jsonDecode(body);
}

Future<dynamic> _decodeLargeJson(String body) =>
    Isolate.run<dynamic>(() => jsonDecode(body));

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
