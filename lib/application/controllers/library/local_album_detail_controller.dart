import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart' as identity;

class LocalAlbumDetailController extends FeatureController {
  final AppController app;
  final OfflineAlbumGroup initialAlbum;
  late final _selection = ControllerSelection<String>(update);

  LocalAlbumDetailController(this.app, this.initialAlbum);

  bool get selectionMode => _selection.active;

  set selectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedTrackIds => _selection.keys();

  Future<void> removeDownloads(List<Track> tracks, {required String label}) async {
    final album = currentAlbum(app);

    await app.removeDownloadedTracks(
      tracks,
      label: label,
      scope: tracks.length == album.tracks.length
          ? OfflineDeletionScope.album(id: album.id, label: label)
          : const OfflineDeletionScope.track(),
    );

    if (!isDisposed) {
      clearSelection();
    }
  }

  List<Track> selectedTracks(List<Track> tracks) {
    return tracks.where((track) => selectedTrackIds.contains(selectionKey(track))).toList(growable: false);
  }

  void toggleSelection(Track track) {
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

  OfflineAlbumGroup currentAlbum(AppController controller) {
    final groups = offlineArtistGroups(controller.offlineTracks);

    for (final artist in groups) {
      for (final album in artist.albums) {
        if (album.id == initialAlbum.id) {
          return album;
        }
      }
    }

    return OfflineAlbumGroup(
      id: initialAlbum.id,
      title: initialAlbum.title,
      artist: initialAlbum.artist,
      artistId: initialAlbum.artistId,
      tracks: const <Track>[],
      coverPath: initialAlbum.coverPath,
    );
  }

  OfflineTrackDownload? offlineDownloadForTrack(AppController controller, Track track) {
    final available = controller.availableOfflineDownloadForTrack(track.id);

    return controller.offlineDownloadForTrack(track.id) ?? available;
  }

  void enterSelection(Track track) {
    _selection.enter(selectionKey(track));
  }

  void startSelection() {
    _selection.clear(activate: true);
  }
}
