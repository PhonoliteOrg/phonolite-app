import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/playback/vehicle_item.dart';
import 'package:phonolite_app/data/models/playback/vehicle_request.dart';
import 'package:phonolite_app/data/models/playback/vehicle_response.dart';

/// Owns the native vehicle channel's method names and payload representation.
class VehicleSurfaceCodec {
  static VehicleRequest decodeRequest(String method, Map<String, dynamic> arguments) {
    final operation = switch (method) {
      'getCarPlayState' => VehicleOperation.getState,
      'getHomeActions' => VehicleOperation.getHomeActions,
      'getAuthState' => VehicleOperation.getAuthorization,
      'getArtists' => VehicleOperation.getArtists,
      'getAlbums' => VehicleOperation.getAlbums,
      'getPlaylists' => VehicleOperation.getPlaylists,
      'getLibraryStatus' => VehicleOperation.getLibraryStatus,
      'playAlbum' => VehicleOperation.playAlbum,
      'playPlaylist' => VehicleOperation.playPlaylist,
      'playLiked' => VehicleOperation.playLiked,
      'startShuffle' ||
      'startLibraryShuffle' ||
      'startLikedShuffle' ||
      'startCustomShuffle' => VehicleOperation.startShuffle,
      _ => VehicleOperation.unknown,
    };
    final legacyShuffle =
        method == 'startLibraryShuffle' || method == 'startLikedShuffle' || method == 'startCustomShuffle';
    final kind = switch (method) {
      'startLikedShuffle' => 'liked',
      'startCustomShuffle' => 'custom',
      'startLibraryShuffle' => 'library',
      _ => arguments['kind']?.toString() ?? 'library',
    };
    final shuffleKind = switch (kind) {
      'artist' => VehicleShuffleKind.artist,
      'album' => VehicleShuffleKind.album,
      'playlist' => VehicleShuffleKind.playlist,
      'custom' => VehicleShuffleKind.custom,
      'liked' => VehicleShuffleKind.liked,
      _ => VehicleShuffleKind.library,
    };

    return VehicleRequest(
      operation: operation,
      scope: !legacyShuffle && arguments['scope']?.toString() == 'local' ? ActionScope.local : ActionScope.server,
      shuffleKind: shuffleKind,
      artistId: arguments['artistId']?.toString(),
      albumId: arguments['albumId']?.toString(),
      playlistId: arguments['playlistId']?.toString(),
    );
  }

  static Map<String, dynamic> encodeResponse(VehicleResponse response) => switch (response) {
    VehicleCommandResult(:final failure) =>
      failure == null ? {'ok': true} : {'error': _failureCode(failure), 'items': const []},
    VehicleItems(:final items) => {'items': items.map(_encodeItem).toList()},
    VehicleSourceState(:final serverAvailable, :final localAvailable, :final hasAnySource) => {
      'serverAvailable': serverAvailable,
      'localAvailable': localAvailable,
      'hasAnySource': hasAnySource,
    },
    VehicleAuthorizationState(:final authorized, :final hasSession, :final status) => {
      'authorized': authorized,
      'hasSession': hasSession,
      'status': status.name,
    },
    VehicleLibraryStatus(:final likedAvailable, :final failure) => {
      'likedAvailable': likedAvailable,
      if (failure != null) 'error': _failureCode(failure),
    },
  };

  static Map<String, dynamic> _encodeItem(VehicleItem item) {
    final path = item.artworkPath?.trim();
    final artworkUrl = item.artworkUrl ?? (path == null || path.isEmpty ? null : Uri.file(path).toString());
    final actionId = switch (item.action) {
      VehicleHomeAction.libraryShuffle => 'startLibraryShuffle',
      VehicleHomeAction.likedShuffle => 'startLikedShuffle',
      VehicleHomeAction.customShuffle => 'startCustomShuffle',
      null => null,
    };

    return {
      'id': item.id ?? actionId!,
      'title': item.title,
      'subtitle': item.subtitle,
      if (item.enabled != null) 'enabled': item.enabled,
      if (artworkUrl != null) 'artworkUrl': artworkUrl,
      if (artworkUrl != null && item.token != null) ...{'token': item.token, 'serverPin': item.serverPin},
    };
  }

  static String _failureCode(VehicleFailure failure) => switch (failure) {
    VehicleFailure.unauthorized => 'unauthorized',
    VehicleFailure.serverUnavailable => 'server_unavailable',
    VehicleFailure.missingArtist => 'missing_artist',
    VehicleFailure.missingAlbum => 'missing_album',
    VehicleFailure.missingPlaylist => 'missing_playlist',
    VehicleFailure.likedEmpty => 'liked_empty',
    VehicleFailure.customEmpty => 'custom_empty',
  };
}
