import 'dart:async';

import 'package:phonolite_app/data/models/collections/playlist.dart';

typedef PlaylistTrackMutation = FutureOr<void> Function(Playlist playlist);

class PlaylistTrackActions {
  final List<Playlist> playlists;

  /// Authoritative playlist updates for this action's scope.
  /// The modal owns its subscription; null keeps a standalone static list.
  final Stream<List<Playlist>>? playlistChanges;
  final String trackId;
  final bool canUsePlaylists;
  final PlaylistTrackMutation add;
  final PlaylistTrackMutation remove;
  final bool Function(Playlist playlist)? containsTrack;

  PlaylistTrackActions({
    required this.playlists,
    required this.trackId,
    required this.canUsePlaylists,
    required this.add,
    required this.remove,
    this.playlistChanges,
    this.containsTrack,
  });
}
