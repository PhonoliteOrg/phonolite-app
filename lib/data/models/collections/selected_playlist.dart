import 'package:phonolite_app/data/models/collections/playlist.dart';

class SelectedPlaylist {
  final Playlist playlist;
  final bool isLocal;

  const SelectedPlaylist({required this.playlist, required this.isLocal});
}
