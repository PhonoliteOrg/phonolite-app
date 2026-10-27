import 'package:phonolite_app/data/models/collections/like_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';

/// A complete, revision-consistent account collection snapshot.
///
/// Likes include unlike records. Missing IDs are also unliked; consumers replace
/// membership rather than merging this snapshot into their old membership.
class AccountCollectionSnapshot {
  final String userId;
  final int revision;
  final List<ServerLikeState> likes;
  final List<Playlist> playlists;

  AccountCollectionSnapshot({
    required this.userId,
    required this.revision,
    required Iterable<ServerLikeState> likes,
    required Iterable<Playlist> playlists,
  }) : likes = List.unmodifiable(likes),
       playlists = List.unmodifiable(
         playlists.map((playlist) => playlist.copyWith(trackIds: List.unmodifiable(playlist.trackIds))),
       );

  factory AccountCollectionSnapshot.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final revision = json['revision'];
    final likes = json['likes'];
    final playlists = json['playlists'];

    if (userId is! String ||
        userId.isEmpty ||
        revision is! int ||
        revision < 0 ||
        likes is! List ||
        playlists is! List) {
      throw const FormatException('Invalid account collection snapshot');
    }

    return AccountCollectionSnapshot(
      userId: userId,
      revision: revision,
      likes: likes.map((item) => ServerLikeState.fromJson(Map<String, dynamic>.from(item as Map))),
      playlists: playlists.map((item) => Playlist.fromJson(Map<String, dynamic>.from(item as Map))),
    );
  }

  Set<String> get likedTrackIds => Set.unmodifiable(likes.where((state) => state.liked).map((state) => state.trackId));

  Set<String> get playlistTrackIds => Set.unmodifiable(playlists.expand((playlist) => playlist.trackIds));
}
