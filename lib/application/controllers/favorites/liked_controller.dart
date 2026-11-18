import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/downloads/downloaded_track_selection.dart';
import 'package:phonolite_app/data/models/collections/playlist_image_edit.dart';
import 'package:phonolite_app/data/models/collections/playlist_editor_values.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/track_selection_key.dart' as identity;

class LikedController extends FeatureController {
  final AppController app;
  int? _requestedServerRevision;
  late final _selection = ControllerSelection<String>(update, groups: const ['local', 'server']);

  LikedController(this.app);

  bool get selectionMode => _selection.active;

  set selectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedLocalTrackIds => _selection.keys('local');

  Set<String> get selectedServerTrackIds => _selection.keys('server');

  @override
  Future<void> initializeFeature() {
    final loading = app.loadLocalLikedTracks();

    listenTo(app.authStream, (_) => unawaited(loadIfNeeded().catchError(reportInitializationFailure)));
    final serverLoading = loadIfNeeded();

    return Future.wait([loading, serverLoading]);
  }

  Future<void> loadIfNeeded() {
    if (isDisposed || !app.authState.isAuthorized) {
      return Future<void>.value();
    }
    final revision = app.connection.sessionRevision;
    if (_requestedServerRevision != revision) {
      clearSelection();
    }
    if (_requestedServerRevision == revision) {
      return Future<void>.value();
    }

    _requestedServerRevision = revision;

    return app.loadLikedTracks();
  }

  /// The source a new liked-tracks playlist defaults to: the only one with tracks, otherwise the one shown first.
  PlaylistEditorTarget playlistTargetFor({
    required List<Track> localTracks,
    required List<Track> serverTracks,
    required bool localFirst,
  }) {
    if (serverTracks.isEmpty) {
      return PlaylistEditorTarget.local;
    }

    if (localTracks.isEmpty) {
      return PlaylistEditorTarget.server;
    }

    return localFirst ? PlaylistEditorTarget.local : PlaylistEditorTarget.server;
  }

  /// Describes what [createPlaylistFromLiked] will add for [target], using the current liked tracks.
  String playlistMessageFor(PlaylistEditorTarget target) {
    final (count, source) = switch (target) {
      PlaylistEditorTarget.local => (app.localLiked.length, 'local'),
      PlaylistEditorTarget.server => (app.liked.length, 'server'),
    };
    final tracks = count == 1 ? 'track' : 'tracks';

    return 'Your $count $source liked $tracks will be added to this new $source playlist, in the order shown.';
  }

  /// Creates a playlist on [target] holding that source's current liked tracks in their shown order.
  ///
  /// Local liked tracks become a local playlist and server liked tracks a server playlist.
  Future<void> createPlaylistFromLiked(
    String name, {
    required String description,
    required PlaylistImageEdit imageEdit,
    required PlaylistEditorTarget target,
  }) {
    return switch (target) {
      PlaylistEditorTarget.local => app.createLocalPlaylist(
        name,
        description: description,
        imageEdit: imageEdit,
        tracks: List.of(app.localLiked),
      ),
      PlaylistEditorTarget.server => app.createPlaylist(
        name,
        description: description,
        imageEdit: imageEdit,
        tracks: List.of(app.liked),
      ),
    };
  }

  Future<void> removeDownloads(List<Track> tracks, {required String label}) async {
    await app.removeDownloadedTracks(tracks, label: label);

    if (!isDisposed) {
      clearSelection();
    }
  }

  List<Track> selectedTracks(List<Track> tracks, Set<String> selectedIds) {
    return tracks.where((track) => selectedIds.contains(selectionKey(track))).toList(growable: false);
  }

  void toggleSelection(AppController controller, Track track, {required bool local}) {
    if (!canRemoveTrack(controller, track)) {
      return;
    }

    final key = selectionKey(track);

    _selection.toggle(key, group: local ? 'local' : 'server');
  }

  void selectAll({required List<Track> localTracks, required List<Track> serverTracks}) {
    _selection.replaceGroups({'local': localTracks.map(selectionKey), 'server': serverTracks.map(selectionKey)});
  }

  void deselectAll() {
    _selection.clear(activate: true);
  }

  void clearSelection() {
    _selection.clear();
  }

  String selectionKey(Track track) {
    return identity.trackSelectionKey(track);
  }

  List<Track> removableTracks(AppController controller, List<Track> tracks) {
    return DownloadedTrackSelection(controller).removable(tracks);
  }

  bool canRemoveTrack(AppController controller, Track track) {
    return DownloadedTrackSelection(controller).canRemove(track);
  }

  void startSelection() {
    _selection.clear(activate: true);
  }

  void enterSelection(AppController controller, Track track, {required bool local}) {
    if (!canRemoveTrack(controller, track)) {
      return;
    }

    _selection.enter(selectionKey(track), group: local ? 'local' : 'server');
  }
}
