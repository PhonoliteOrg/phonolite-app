import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/selected_playlist.dart';

export 'package:phonolite_app/data/models/collections/selected_playlist.dart';

class PlaylistsController extends FeatureController {
  final AppController app;
  bool _requestedServerLoad = false;
  late final _selection = ControllerSelection<String>(update);
  final Set<String> _deletingPlaylistKeys = <String>{};

  PlaylistsController(this.app);

  Set<String> get deletingPlaylistKeys => Set.unmodifiable(_deletingPlaylistKeys);

  bool get selectionMode => _selection.active;

  set selectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedPlaylistKeys => _selection.keys();

  @override
  Future<void> initializeFeature() {
    final loading = app.loadLocalPlaylists();

    listenTo(app.authStream, (_) => unawaited(loadIfNeeded().catchError(reportInitializationFailure)));
    final serverLoading = loadIfNeeded();

    return Future.wait([loading, serverLoading]);
  }

  Future<void> loadIfNeeded() {
    if (isDisposed || !app.authState.isAuthorized || _requestedServerLoad || app.playlists.isNotEmpty) {
      return Future<void>.value();
    }

    _requestedServerLoad = true;

    return app.loadPlaylists();
  }

  Future<void> deletePlaylists(List<SelectedPlaylist> selected) async {
    final controller = app;
    final keys = selected.map((item) => selectionKey(item.playlist, isLocal: item.isLocal)).toSet();

    update(() => _deletingPlaylistKeys.addAll(keys));

    try {
      for (final item in selected) {
        if (item.isLocal) {
          await controller.deleteLocalPlaylist(item.playlist.id);
        } else {
          await controller.deletePlaylist(item.playlist.id);
        }
      }

      if (!isDisposed) {
        _deletingPlaylistKeys.removeAll(keys);
        _selection.removeKeys(keys, activate: false);
      }
    } finally {
      if (!isDisposed) {
        update(() => _deletingPlaylistKeys.removeAll(keys));
      }
    }
  }

  List<SelectedPlaylist> selectedPlaylists({
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) {
    Iterable<SelectedPlaylist> selectedFrom(List<Playlist> playlists, {required bool isLocal}) => playlists
        .where((playlist) => selectedPlaylistKeys.contains(selectionKey(playlist, isLocal: isLocal)))
        .map((playlist) => SelectedPlaylist(playlist: playlist, isLocal: isLocal));

    return [...selectedFrom(localPlaylists, isLocal: true), ...selectedFrom(serverPlaylists, isLocal: false)];
  }

  void startSelection() {
    _selection.clear(activate: true);
  }

  void clearSelection() {
    _selection.clear();
  }

  void deselectAll() {
    _selection.clear(activate: null);
  }

  void selectAll({required List<Playlist> localPlaylists, required List<Playlist> serverPlaylists}) {
    _selection.replace([
      ...localPlaylists.map((playlist) => selectionKey(playlist, isLocal: true)),
      ...serverPlaylists.map((playlist) => selectionKey(playlist, isLocal: false)),
    ], activate: null);
  }

  void toggleSelection(Playlist playlist, {required bool isLocal}) {
    final key = selectionKey(playlist, isLocal: isLocal);

    _selection.toggle(key, activate: null);
  }

  String selectionKey(Playlist playlist, {required bool isLocal}) {
    return '${isLocal ? 'local' : 'server'}:${playlist.id}';
  }

  String? serverPlaylistCoverUrl(AppController controller, Playlist playlist) {
    final imageRef = playlist.imageRef?.trim();

    if (imageRef == null || imageRef.isEmpty) {
      return null;
    }

    return controller.connection.buildPlaylistCoverUrl(playlist.id, imageRef: imageRef);
  }
}
