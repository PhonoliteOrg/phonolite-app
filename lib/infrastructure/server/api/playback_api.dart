import 'dart:async';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/playback_settings_response.dart';
import 'package:phonolite_app/data/models/server/server_ports_response.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class PlaybackApi extends JsonApiEndpoint {
  PlaybackApi(super.transport);

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
