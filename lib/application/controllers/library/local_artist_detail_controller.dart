import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/downloads/downloaded_track_selection.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart' as identity;

class LocalArtistDetailController extends FeatureController {
  final AppController app;
  final OfflineArtistGroup initialGroup;
  late final _selection = ControllerSelection<String>(update);

  LocalArtistDetailController(this.app, this.initialGroup);

  bool get albumSelectionMode => _selection.active;

  set albumSelectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedAlbumIds => _selection.keys();

  List<Track> tracksForAlbums(List<OfflineAlbumGroup> albums) => [for (final album in albums) ...album.tracks];

  Future<void> removeAlbumDownloads(List<OfflineAlbumGroup> albums, String label) async {
    await app.removeDownloadedTracks(
      tracksForAlbums(albums),
      label: label,
      scope: OfflineDeletionScope.album(id: albums.length == 1 ? albums.single.id : null, label: label),
    );

    if (!isDisposed) {
      clearAlbumSelection();
    }
  }

  Set<String> removableAlbumIds(List<OfflineAlbumGroup> albums) {
    return <String>{
      for (final album in albums)
        if (album.tracks.isNotEmpty) albumSelectionKey(album),
    };
  }

  List<OfflineAlbumGroup> selectedAlbums(List<OfflineAlbumGroup> albums, Set<String> removableIds) {
    bool isSelectedAndRemovable(OfflineAlbumGroup album) {
      final key = albumSelectionKey(album);

      return removableIds.contains(key) && selectedAlbumIds.contains(key);
    }

    return albums.where(isSelectedAndRemovable).toList(growable: false);
  }

  void toggleAlbumSelection(OfflineAlbumGroup album) {
    final key = albumSelectionKey(album);

    _selection.toggle(key);
  }

  void selectAllAlbums(Set<String> albumIds) {
    _selection.replace(albumIds);
  }

  void deselectAllAlbums() {
    _selection.clear(activate: true);
  }

  void clearAlbumSelection() {
    _selection.clear();
  }

  String albumSelectionKey(OfflineAlbumGroup album) => album.id;

  OfflineArtistGroup currentGroup(AppController controller) {
    final groups = offlineArtistGroups(controller.offlineTracks);

    for (final group in groups) {
      if (group.id == initialGroup.id) {
        return group;
      }
    }

    return OfflineArtistGroup(
      id: initialGroup.id,
      name: initialGroup.name,
      albums: const <OfflineAlbumGroup>[],
      coverPath: initialGroup.coverPath,
      bannerPath: initialGroup.bannerPath,
    );
  }

  void startAlbumSelection() {
    _selection.clear(activate: true);
  }

  Set<String> removingTrackIds(AppController controller) {
    return DownloadedTrackSelection(controller).removingIdentities;
  }

  bool albumHasRemovingTracks(OfflineAlbumGroup album, Set<String> removingTrackIds) {
    if (removingTrackIds.isEmpty) {
      return false;
    }

    return album.tracks.any((track) => trackMatchesAnyIdentity(track, removingTrackIds));
  }

  bool trackMatchesAnyIdentity(Track track, Set<String> ids) {
    return identity.trackMatchesAnyIdentity(track, ids);
  }
}
