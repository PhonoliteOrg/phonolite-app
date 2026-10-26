import 'dart:async';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/playback_settings_response.dart';
import 'package:phonolite_app/data/models/server/server_ports_response.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class PlaybackApi extends JsonApiEndpoint {
  PlaybackApi(super.transport);

  Future<ShuffleSessionPage> createShuffleSession({
    required String mode,
    required String clientId,
    required String requestId,
    String? artistId,
    String? albumId,
    List<String> artistIds = const [],
    List<String> genres = const [],
    String? playlistId,
    String? startTrackId,
  }) => postValue('/library/shuffle/sessions', {
    'mode': mode,
    'client_id': clientId,
    'request_id': requestId,
    'limit': 10,
    if (artistId != null) 'artist_id': artistId,
    if (albumId != null) 'album_id': albumId,
    'artist_ids': artistIds,
    'genres': genres,
    if (playlistId != null) 'playlist_id': playlistId,
    if (startTrackId != null) 'start_track_id': startTrackId,
  }, ShuffleSessionPage.fromJson);

  Future<ShuffleSessionPage> fetchShuffleSessionPage(
    String sessionId, {
    required String clientId,
    required int offset,
  }) {
    final id = ApiTransport.encodePathSegment(sessionId);
    final client = Uri.encodeQueryComponent(clientId);
    return getValue(
      '/library/shuffle/sessions/$id?client_id=$client&offset=$offset&limit=10',
      ShuffleSessionPage.fromJson,
    );
  }

  Future<void> releaseShuffleSession(String sessionId, {required String clientId}) async {
    final id = ApiTransport.encodePathSegment(sessionId);
    final client = Uri.encodeQueryComponent(clientId);
    final uri = Uri.parse('${transport.baseUrl}/library/shuffle/sessions/$id?client_id=$client');
    final headers = transport.buildHeaders();
    // Best-effort cleanup must not change availability for active playback.
    await transport.client.delete(uri, headers: headers).timeout(ApiTransport.defaultRequestTimeout);
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

    return getValues(path, Track.fromJson);
  }

  Future<PlaybackSettingsResponse> fetchPlaybackSettings({
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) async {
    return getValue('/player/settings', PlaybackSettingsResponse.fromJson, timeout: timeout, retryable: retryable);
  }

  Future<void> updatePlaybackSettings({required String repeatMode}) async {
    await transport.postVoid('/player/settings', {'repeat_mode': repeatMode});
  }

  Future<ServerPortsResponse> fetchServerPorts({
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) async {
    return getValue('/server/ports', ServerPortsResponse.fromJson, timeout: timeout, retryable: retryable);
  }
}
