import 'package:phonolite_app/data/models/collections/playlist.dart';

class PlaylistTrackActions {
  final List<Playlist> playlists;
  final String trackId;
  final bool canUsePlaylists;
  final void Function(Playlist) add;
  final void Function(Playlist) remove;

  PlaylistTrackActions({
    required this.playlists,
    required this.trackId,
    required this.canUsePlaylists,
    required this.add,
    required this.remove,
  });
}
