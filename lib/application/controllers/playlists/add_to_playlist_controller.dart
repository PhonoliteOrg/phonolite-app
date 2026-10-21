import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_track_actions.dart';
import 'package:phonolite_app/data/models/library/track.dart';

export 'package:phonolite_app/data/models/collections/playlist_track_actions.dart';

class AddToPlaylistController extends FeatureController {
  String _query = '';
  final _added = <String>{};
  final _removed = <String>{};

  String get query => _query;

  void setQuery(String value) => update(() => _query = value);

  List<Playlist> filter(List<Playlist> playlists) {
    final normalized = _query.trim().toLowerCase();

    return playlists
        .where((playlist) => normalized.isEmpty || playlist.name.toLowerCase().contains(normalized))
        .toList();
  }

  bool contains(Playlist playlist, String trackId) =>
      (playlist.trackIds.contains(trackId) || _added.contains(playlist.id)) && !_removed.contains(playlist.id);

  int trackCount(Playlist playlist, String trackId) {
    final existing = playlist.trackIds.contains(trackId);
    final count = playlist.trackIds.length;

    if (existing && _removed.contains(playlist.id)) {
      return count - 1;
    }

    if (!existing && _added.contains(playlist.id)) {
      return count + 1;
    }

    return count;
  }

  void add(Playlist playlist, void Function(Playlist) action) {
    action(playlist);

    void markAdded() {
      _added.add(playlist.id);
      _removed.remove(playlist.id);
    }

    update(markAdded);
  }

  void remove(Playlist playlist, void Function(Playlist) action) {
    action(playlist);

    void markRemoved() {
      _removed.add(playlist.id);
      _added.remove(playlist.id);
    }

    update(markRemoved);
  }

  static Future<PlaylistTrackActions?> prepareActions(AppController app, Track track, ActionScope scope) async {
    final revision = app.catalog.sessionRevision;
    final local = scope == ActionScope.local;

    if (local) {
      if (app.localPlaylists.isEmpty) {
        await app.loadLocalPlaylists();
      }
    } else if (app.authState.isAuthorized && app.playlists.isEmpty) {
      await app.loadPlaylists();
    }

    if (app.catalog.sessionRevision != revision) {
      return null;
    }

    final download = local ? app.availableOfflineDownloadForTrack(track.id) : null;
    final localId = track.localId ?? download?.localTrackId;
    final serverTrack = local ? null : app.serverTrackForCurrentServer(track);

    void removeTrack(Playlist playlist) {
      if (local) {
        app.removeTrackFromLocalPlaylist(playlist, track);
      } else if (serverTrack != null && app.catalog.sessionRevision == revision) {
        app.removeTrackFromPlaylist(playlist, serverTrack);
      }
    }

    void addTrack(Playlist playlist) {
      if (local) {
        app.addTrackToLocalPlaylist(playlist, track);
      } else if (serverTrack != null && app.catalog.sessionRevision == revision) {
        app.addTrackToPlaylist(playlist, serverTrack);
      }
    }

    return PlaylistTrackActions(
      playlists: local ? app.localPlaylists : app.playlists,
      trackId: local ? localId ?? track.id : serverTrack?.id ?? track.id,
      canUsePlaylists: local ? localId != null : serverTrack != null && app.authState.isAuthorized,
      add: addTrack,
      remove: removeTrack,
    );
  }
}
