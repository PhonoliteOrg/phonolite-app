import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/application/controllers/shared/controller_selection.dart';
import 'package:phonolite_app/application/downloads/downloaded_track_selection.dart';
import 'package:phonolite_app/data/models/downloads/collection_download_summary.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_deletion.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart' as identity;

export 'package:phonolite_app/data/models/downloads/collection_download_summary.dart';

class AlbumDetailController extends FeatureController {
  final AppController app;
  late final _selection = ControllerSelection<String>(update);
  late Album _album;

  AlbumDetailController(this.app, Album initialAlbum) : _album = initialAlbum;

  Album get album => _album;

  bool get selectionMode => _selection.active;

  set selectionMode(bool value) => _selection.setActive(value);

  Set<String> get selectedTrackIds => _selection.keys();

  @override
  Future<void> initializeFeature() {
    final loading = app.loadTracks(_album.id);

    listenTo(app.watchAlbum(_album.id), (value) => update(() => _album = value));

    return loading;
  }

  Future<void> removeDownloads(List<Track> tracks, {required String label}) async {
    await app.removeDownloadedTracks(tracks, label: label, scope: const OfflineDeletionScope.track());

    if (!isDisposed) {
      clearSelection();
    }
  }

  List<Track> selectedTracks(List<Track> tracks) {
    return tracks.where((track) => selectedTrackIds.contains(selectionKey(track))).toList(growable: false);
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

  static CollectionDownloadSummary summarizeDownloads(AppController controller, List<Track> tracks) {
    var downloaded = 0;
    var active = 0;
    var failed = 0;

    for (final track in tracks) {
      final download = controller.offlineDownloadForTrack(track.id);

      if (controller.availableOfflineDownloadForTrack(track.id) != null) {
        downloaded++;
      } else if (download?.status == OfflineDownloadStatus.queued ||
          download?.status == OfflineDownloadStatus.preparing ||
          download?.status == OfflineDownloadStatus.downloading ||
          download?.status == OfflineDownloadStatus.validating ||
          download?.status == OfflineDownloadStatus.removing) {
        active++;
      } else if (download?.status == OfflineDownloadStatus.failed) {
        failed++;
      }
    }

    return CollectionDownloadSummary(total: tracks.length, downloaded: downloaded, active: active, failed: failed);
  }
}
