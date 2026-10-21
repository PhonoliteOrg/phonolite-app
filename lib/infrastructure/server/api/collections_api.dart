import 'dart:async';

import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class CollectionsApi extends JsonApiEndpoint {
  final Future<List<ServerLikeState>> Function(Map<String, bool> states) _updateLikeStates;

  CollectionsApi(super.transport, {required Future<List<ServerLikeState>> Function(Map<String, bool>) updateLikeStates})
    : _updateLikeStates = updateLikeStates;

  Future<List<Playlist>> fetchPlaylists() async {
    return getValues('/library/playlists', Playlist.fromJson);
  }

  Future<List<Track>> fetchPlaylistTracks(String playlistId) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    return getValues('/browse/playlists/$encoded/tracks', Track.fromJson);
  }

  Future<List<Track>> fetchLikedTracks() async {
    return getValues('/browse/likes', Track.fromJson);
  }

  Future<void> likeTrack(String trackId) async {
    final encoded = ApiTransport.encodePathSegment(trackId);

    await transport.postVoid('/library/likes/$encoded', {});
  }

  Future<void> unlikeTrack(String trackId) async {
    final encoded = ApiTransport.encodePathSegment(trackId);

    await transport.delete('/library/likes/$encoded');
  }

  Future<List<ServerLikeState>> updateLikeStates(
    Map<String, bool> states, {
    Map<String, int> updatedAtByTrack = const <String, int>{},
  }) async {
    if (states.isEmpty) {
      return const <ServerLikeState>[];
    }

    Map<String, Object> encodeLikeState(MapEntry<String, bool> entry) {
      final updatedAt = updatedAtByTrack[entry.key];

      return {
        'track_id': entry.key,
        'liked': entry.value,
        if (updatedAt != null && updatedAt > 0) 'updated_at': updatedAt,
      };
    }

    final response = await transport.postList('/library/likes/batch', {
      'items': states.entries.map(encodeLikeState).toList(growable: false),
    });

    return response
        .map((item) => ServerLikeState.fromJson(item))
        .where((item) => item.trackId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<ServerLikeState?> setLikeState(String trackId, bool liked) async {
    final states = await _updateLikeStates({trackId: liked});

    return states.isEmpty ? null : states.first;
  }

  Future<Playlist> createPlaylist(String name, {String? description}) async {
    return postValue('/library/playlists', {'name': name, 'description': description?.trim() ?? ''}, Playlist.fromJson);
  }

  Future<Playlist> renamePlaylist(String playlistId, String name, {String? description}) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    return postValue('/library/playlists/$encoded', {
      'name': name,
      'description': description?.trim() ?? '',
    }, Playlist.fromJson);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    await transport.delete('/library/playlists/$encoded');
  }

  Future<Playlist> uploadPlaylistCover(String playlistId, List<int> bytes, String contentType) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    final response = await transport.executeRequest(
      () => transport.client.put(
        Uri.parse('${transport.baseUrl}/library/playlists/$encoded/cover'),
        headers: transport.buildHeaders(contentTypeValue: contentType),
        body: bytes,
      ),
      label: 'PUT playlist cover',
    );

    return Playlist.fromJson(await transport.decode(response));
  }

  Future<Playlist> deletePlaylistCover(String playlistId) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    final response = await transport.executeRequest(
      () => transport.client.delete(
        Uri.parse('${transport.baseUrl}/library/playlists/$encoded/cover'),
        headers: transport.buildHeaders(),
      ),
      label: 'DELETE playlist cover',
    );

    return Playlist.fromJson(await transport.decode(response));
  }

  Future<Playlist> updatePlaylistTracks(String playlistId, List<String> trackIds) async {
    final encoded = ApiTransport.encodePathSegment(playlistId);

    return postValue('/library/playlists/$encoded', {'track_ids': trackIds}, Playlist.fromJson);
  }
}
