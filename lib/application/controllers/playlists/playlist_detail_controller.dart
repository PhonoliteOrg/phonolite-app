import 'dart:async';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/downloads/downloaded_track_selection.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart' as identity;
import 'package:phonolite_app/data/storage/logs/app_log.dart';

class PlaylistDetailController extends FeatureController {
  final AppController app;
  String _playlistId;
  bool _isLocal;
  bool _tracksLoading = true;
  String? _activeTracksLoadKey;
  late final _trackRequests = createRequestGeneration();
  late final _selection = ControllerSelection<String>(update);

  PlaylistDetailController(this.app, this._playlistId, this._isLocal);

  String get playlistId => _playlistId;

  bool get isLocal => _isLocal;

  bool get tracksLoading => _tracksLoading;

  bool get playlistDeleted =>
      !_isLocal && app.serverCollectionsLoaded && !app.playlists.any((playlist) => playlist.id == _playlistId);

  bool get selectionMode => _selection.active;

  set selectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedTrackIds => _selection.keys();

  String get tracksLoadKey {
    return _isLocal ? 'local:$_playlistId' : 'server:${app.connection.sessionRevision}:$_playlistId';
  }

  /// The scope that track actions such as adding to another playlist apply to.
  ActionScope get actionScope => _isLocal ? ActionScope.local : ActionScope.server;

  /// This page's playlist within [playlists]. Until the published list contains it,
  /// a placeholder with the same ID keeps the page's frame stable.
  Playlist playlistFrom(List<Playlist> playlists) => playlists.firstWhere(
    (playlist) => playlist.id == _playlistId,
    orElse: () => Playlist(id: _playlistId, name: 'Playlist', trackIds: const []),
  );

  /// This playlist's local entries within [entries], in their published order.
  List<LocalPlaylistEntry> entriesFrom(List<LocalPlaylistEntry> entries) =>
      entries.where((entry) => entry.playlistId == _playlistId).toList(growable: false);

  /// The tracks to show; none while this playlist's tracks are loading.
  List<Track> displayedTracks(List<Track> tracks) => _tracksLoading ? const <Track>[] : tracks;

  /// The playlist's cover: its local image path, or the server rendition URL.
  String? coverUrl(Playlist playlist) => _isLocal ? playlist.imagePath : serverPlaylistCoverUrl(app, playlist);

  void setPlaylist(String id, bool local) {
    if (isDisposed) {
      return;
    }

    _playlistId = id;
    _isLocal = local;

    loadTracksIfNeeded(app, force: true);
  }

  Future<void> playFromTop() =>
      _isLocal ? app.playLocalPlaylistFromTop(_playlistId) : app.playPlaylistFromTop(_playlistId);

  Future<void> playFrom(Track track) => _isLocal
      ? app.queueLocalPlaylist(_playlistId, startTrackId: track.id)
      : app.queuePlaylist(_playlistId, startTrackId: track.id);

  Future<void> rename(
    String name, {
    String? description,
    PlaylistImageEdit imageEdit = const PlaylistImageEdit.keep(),
  }) => _isLocal
      ? app.renameLocalPlaylist(_playlistId, name, description: description, imageEdit: imageEdit)
      : app.renamePlaylist(_playlistId, name, description: description, imageEdit: imageEdit);

  Future<void> toggleLike(Track track) => _isLocal ? app.toggleLocalLike(track) : app.toggleLike(track);

  Future<void> removeDownloads(List<Track> tracks, {required String label}) async {
    await app.removeDownloadedTracks(tracks, label: label);

    if (!isDisposed) {
      clearSelection();
    }
  }

  List<Track> selectedTracks(List<Track> tracks) {
    return tracks.where((track) => selectedTrackIds.contains(selectionKey(track))).toList(growable: false);
  }

  LocalPlaylistEntry? localEntryForTrack(Track track) {
    if (!_isLocal) {
      return null;
    }

    final entries = entriesFrom(app.localPlaylistEntries);

    for (final entry in entries) {
      if (identical(entry.track, track)) {
        return entry;
      }
    }

    for (final entry in entries) {
      if (entry.track.id == track.id && entry.track.serverBaseUrl == track.serverBaseUrl) {
        return entry;
      }
    }

    return null;
  }

  bool isTrackPlayable(Track track) => localEntryForTrack(track)?.isPlayable ?? true;

  OfflineTrackDownload? offlineDownloadForTrack(Track track) {
    final entry = localEntryForTrack(track);

    return entry == null ? app.offlineDownloadForTrack(track.id) : app.offlineDownloadForLocalPlaylistEntry(entry);
  }

  OfflineDownloadStatus? downloadStatusForTrack(Track track) =>
      offlineDownloadForTrack(track)?.status ?? localEntryForTrack(track)?.status;

  Future<void> retryTrackDownload(Track track) async {
    final entry = localEntryForTrack(track);

    if (entry != null) {
      await app.retryLocalPlaylistEntry(entry);
    }
  }

  Future<void> continueTrackDownload(Track track) async {
    final entry = localEntryForTrack(track);

    if (entry != null) {
      await app.resumeLocalPlaylistEntry(entry);
    }
  }

  void toggleSelection(AppController controller, Track track) {
    if (!canRemoveTrack(controller, track)) {
      return;
    }

    final key = selectionKey(track);

    _selection.toggle(key);
  }

  void selectAll(List<Track> tracks) {
    _selection.replace(tracks.map(selectionKey));
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

  void enterSelection(AppController controller, Track track) {
    if (!canRemoveTrack(controller, track)) {
      return;
    }

    _selection.enter(selectionKey(track));
  }

  void startSelection() {
    _selection.clear(activate: true);
  }

  void loadTracksIfNeeded(AppController controller, {bool force = false}) {
    if (isDisposed) {
      return;
    }

    final key = tracksLoadKey;

    if (!force && _activeTracksLoadKey == key) {
      return;
    }

    _activeTracksLoadKey = key;
    final requestId = _trackRequests.advance();

    if (!_tracksLoading || selectionMode || selectedTrackIds.isNotEmpty) {
      _tracksLoading = true;
      _selection.clear();
    }

    final loadFuture = _isLocal
        ? controller.loadLocalPlaylistEntries(_playlistId)
        : controller.loadPlaylistTracks(_playlistId);

    void finishTrackLoading() {
      if (!_trackRequests.isCurrent(requestId) || tracksLoadKey != key) {
        return;
      }

      update(() => _tracksLoading = false);
    }

    unawaited(loadFuture.whenComplete(finishTrackLoading).catchError(_reportTrackLoadFailure));
  }

  void _reportTrackLoadFailure(Object error) {
    AppLogger.warning('Could not load playlist tracks: $error');
  }

  String? serverPlaylistCoverUrl(AppController controller, Playlist playlist) {
    final imageRef = playlist.imageRef?.trim();

    if (imageRef == null || imageRef.isEmpty) {
      return null;
    }

    return controller.connection.buildPlaylistCoverUrl(playlist.id, imageRef: imageRef);
  }

  Album playlistAlbum(Playlist playlist) {
    return Album(
      id: playlist.id,
      title: playlist.name,
      artist: 'Playlist',
      artistId: '',
      trackCount: playlist.totalTrackCount,
      summary: playlist.description,
    );
  }
}
