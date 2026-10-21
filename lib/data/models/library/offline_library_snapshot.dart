import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart' as offline_views;

class OfflineLibrarySnapshot {
  final List<Track> tracks;
  final List<offline_views.OfflineArtistGroup> artistGroups;
  final List<Track> liked;
  final List<Playlist> playlists;
  final List<Track> playlistTracks;
  final int revision;

  const OfflineLibrarySnapshot({
    required this.tracks,
    required this.artistGroups,
    required this.liked,
    required this.playlists,
    required this.playlistTracks,
    required this.revision,
  });
}
