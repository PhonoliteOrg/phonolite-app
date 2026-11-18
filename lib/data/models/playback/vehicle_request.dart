import 'package:phonolite_app/data/models/app/action_scope.dart';

enum VehicleOperation {
  getState,
  getHomeActions,
  getAuthorization,
  getArtists,
  getAlbums,
  getPlaylists,
  getLibraryStatus,
  playAlbum,
  playPlaylist,
  playLiked,
  startShuffle,
  unknown,
}

enum VehicleShuffleKind { library, artist, album, playlist, custom, liked }

class VehicleRequest {
  final VehicleOperation operation;
  final ActionScope scope;
  final VehicleShuffleKind shuffleKind;
  final String? artistId;
  final String? albumId;
  final String? playlistId;

  const VehicleRequest({
    required this.operation,
    this.scope = ActionScope.server,
    this.shuffleKind = VehicleShuffleKind.library,
    this.artistId,
    this.albumId,
    this.playlistId,
  });
}
