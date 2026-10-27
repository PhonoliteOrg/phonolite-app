import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/collections/playlist_track_actions.dart';
import 'package:phonolite_app/data/models/library/track.dart';

export 'package:phonolite_app/data/models/collections/playlist_track_actions.dart';

class AddToPlaylistController extends FeatureController {
  final _added = <String>{};
  final _removed = <String>{};
  final _mutating = <String>{};
  String _query = '';
  List<Playlist> _playlists;
  Stream<List<Playlist>>? _playlistChanges;
  StreamSubscription<List<Playlist>>? _playlistSubscription;
  int _sourceRevision = 0;

  AddToPlaylistController({Iterable<Playlist> playlists = const [], Stream<List<Playlist>>? playlistChanges})
    : _playlists = List.unmodifiable(playlists),
      _playlistChanges = playlistChanges;

  String get query => _query;

  List<Playlist> get playlists => _playlists;

  @override
  void initializeFeature() {
    _listenToPlaylistChanges();
  }

  /// Rebinds replaceable widget inputs without retaining the old stream.
  void setPlaylistSource({
    required List<Playlist> playlists,
    Stream<List<Playlist>>? playlistChanges,
    bool resetActions = false,
  }) {
    if (_playlistChanges == playlistChanges && !resetActions) {
      _replacePlaylists(playlists);

      return;
    }

    _sourceRevision++;
    _mutating.clear();
    final subscription = _playlistSubscription;
    _playlistSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel().catchError(reportInitializationFailure));
    }

    _playlistChanges = playlistChanges;
    _replacePlaylists(playlists);
    _listenToPlaylistChanges();
  }

  void setQuery(String value) => update(() => _query = value);

  List<Playlist> filter(List<Playlist> playlists) {
    final normalized = _query.trim().toLowerCase();

    return playlists
        .where((playlist) => normalized.isEmpty || playlist.name.toLowerCase().contains(normalized))
        .toList();
  }

  bool contains(Playlist playlist, String trackId, {bool Function(Playlist)? containsTrack}) =>
      ((containsTrack?.call(playlist) ?? playlist.trackIds.contains(trackId)) || _added.contains(playlist.id)) &&
      !_removed.contains(playlist.id);

  bool isMutating(Playlist playlist) => _mutating.contains(playlist.id);

  int trackCount(Playlist playlist, String trackId, {bool Function(Playlist)? containsTrack}) {
    final existing = containsTrack?.call(playlist) ?? playlist.trackIds.contains(trackId);
    final count = playlist.totalTrackCount;

    if (existing && _removed.contains(playlist.id)) {
      return count - 1;
    }

    if (!existing && _added.contains(playlist.id)) {
      return count + 1;
    }

    return count;
  }

  Future<void> add(Playlist playlist, PlaylistTrackMutation action) => _mutate(playlist, action, added: true);

  Future<void> remove(Playlist playlist, PlaylistTrackMutation action) => _mutate(playlist, action, added: false);

  Future<void> _mutate(Playlist playlist, PlaylistTrackMutation action, {required bool added}) async {
    if (_mutating.contains(playlist.id)) {
      return;
    }

    final revision = _sourceRevision;
    update(() => _mutating.add(playlist.id));

    try {
      await action(playlist);

      if (revision != _sourceRevision) {
        return;
      }

      update(() {
        (added ? _added : _removed).add(playlist.id);
        (added ? _removed : _added).remove(playlist.id);
      });
    } catch (error, stackTrace) {
      reportInitializationFailure(error, stackTrace);
    } finally {
      if (revision == _sourceRevision) {
        update(() => _mutating.remove(playlist.id));
      }
    }
  }

  void _listenToPlaylistChanges() {
    final changes = _playlistChanges;

    if (changes == null || isDisposed) {
      return;
    }

    final revision = _sourceRevision;

    void receivePlaylists(List<Playlist> playlists) {
      if (revision == _sourceRevision) {
        _replacePlaylists(playlists);
      }
    }

    _playlistSubscription = listenTo(changes, receivePlaylists);
  }

  void _replacePlaylists(List<Playlist> playlists) {
    void reconcile() {
      _playlists = List.unmodifiable(playlists);
      _added.clear();
      _removed.clear();
    }

    update(reconcile);
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

    if (!local && app.catalog.sessionRevision != revision) {
      return null;
    }

    final source = app.localPlaylistSourceForTrack(track);
    final localId = local ? await app.resolveLocalPlaylistTrackId(track) : null;
    final serverTrack = local ? null : await app.resolveServerTrackForCurrentServer(track);

    if (!local && app.catalog.sessionRevision != revision) {
      return null;
    }

    Future<void> removeTrack(Playlist playlist) async {
      if (local) {
        await app.removeTrackFromLocalPlaylist(playlist, track);
      } else if (serverTrack != null && app.authState.isAuthorized && app.catalog.sessionRevision == revision) {
        await app.removeTrackFromPlaylist(playlist, serverTrack);
      }
    }

    Future<void> addTrack(Playlist playlist) async {
      if (local) {
        await app.addTrackToLocalPlaylist(playlist, track);
      } else if (serverTrack != null && app.authState.isAuthorized && app.catalog.sessionRevision == revision) {
        await app.addTrackToPlaylist(playlist, serverTrack);
      }
    }

    return PlaylistTrackActions(
      playlists: local ? app.localPlaylists : app.playlists,
      playlistChanges: _watchPlaylists(app, local: local, revision: revision),
      trackId: local ? localId ?? track.id : serverTrack?.id ?? track.id,
      canUsePlaylists: local ? localId != null || source != null : serverTrack != null && app.authState.isAuthorized,
      add: addTrack,
      remove: removeTrack,
      containsTrack: local ? (playlist) => app.localPlaylistContainsTrack(playlist, track) : null,
    );
  }

  static Stream<List<Playlist>> _watchPlaylists(AppController app, {required bool local, required int revision}) {
    late final StreamController<List<Playlist>> controller;
    StreamSubscription<List<Playlist>>? playlistsSubscription;
    StreamSubscription<Object?>? authSubscription;
    var invalidated = false;

    bool isCurrent() =>
        !invalidated && (local || (app.catalog.sessionRevision == revision && app.authState.isAuthorized));

    void publish(List<Playlist> playlists) {
      if (!isCurrent()) {
        invalidated = true;
        controller.add(const []);

        return;
      }

      controller.add(List.unmodifiable(playlists));
    }

    void checkAccount(Object? _) {
      if (!isCurrent()) {
        invalidated = true;
        controller.add(const []);
      }
    }

    void subscribe() {
      final changes = local ? app.localPlaylistsStream : app.playlistsStream;
      playlistsSubscription = changes.listen(publish);

      if (!local) {
        authSubscription = app.authStream.listen(checkAccount);
      }

      publish(local ? app.localPlaylists : app.playlists);
    }

    Future<void> cancel() async {
      await Future.wait([
        if (playlistsSubscription != null) playlistsSubscription!.cancel(),
        if (authSubscription != null) authSubscription!.cancel(),
      ]);
    }

    controller = StreamController<List<Playlist>>(onListen: subscribe, onCancel: cancel);

    return controller.stream;
  }
}
