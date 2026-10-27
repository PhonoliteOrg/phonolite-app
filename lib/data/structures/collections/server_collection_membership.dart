import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';

/// Personalization projected over server metadata without changing its identity.
///
/// A snapshot makes membership authoritative, including absent likes. Before the
/// first snapshot only explicit successful writes override response values. The
/// connection owns account/session scoping and clears this container on changes.
class ServerCollectionMembership {
  final Map<String, bool> _likes = {};
  final Map<String, Set<String>> _playlists = {};
  Set<String> _playlistTrackIds = {};
  bool _hasSnapshot = false;

  bool get hasSnapshot => _hasSnapshot;

  void clear() {
    _likes.clear();
    _playlists.clear();
    _playlistTrackIds = {};
    _hasSnapshot = false;
  }

  void replace(AccountCollectionSnapshot snapshot) {
    _likes.clear();
    _playlists.clear();

    for (final state in snapshot.likes) {
      _likes[state.trackId] = state.liked;
    }

    for (final playlist in snapshot.playlists) {
      _playlists[playlist.id] = playlist.trackIds.toSet();
    }

    _hasSnapshot = true;
    _rebuildPlaylistMembership();
  }

  void recordLike(String trackId, bool liked) {
    _likes[trackId] = liked;
  }

  void recordPlaylist(Playlist playlist) {
    _playlists[playlist.id] = playlist.trackIds.toSet();
    _rebuildPlaylistMembership();
  }

  void recordPlaylistDeleted(String playlistId) {
    _playlists.remove(playlistId);
    _rebuildPlaylistMembership();
  }

  Track project(Track track) {
    final localId = track.localId;
    final usesLocalIdentity = localId != null && track.id == localId && track.id != track.serverTrackId;

    if (usesLocalIdentity) {
      return track;
    }

    final trackId = track.serverTrackId ?? track.id;
    final liked = _likes[trackId] ?? (_hasSnapshot ? false : track.liked);
    final inPlaylists = _playlistTrackIds.contains(trackId) || (!_hasSnapshot && track.inPlaylists);

    if (track.liked == liked && track.inPlaylists == inPlaylists) {
      return track;
    }

    return track.copyWith(liked: liked, inPlaylists: inPlaylists);
  }

  List<Track> projectAll(Iterable<Track> tracks) => tracks.map(project).toList();

  void _rebuildPlaylistMembership() {
    _playlistTrackIds = _playlists.values.expand((ids) => ids).toSet();
  }
}
