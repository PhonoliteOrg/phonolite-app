import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/track_identity.dart';

/// Application capabilities used by every downloaded-track selection family.
/// Track identity itself remains a data rule; availability is app-owned state.
class DownloadedTrackSelection {
  final AppController app;

  const DownloadedTrackSelection(this.app);

  Set<String> get removingIdentities => {
    for (final download in app.offlineDownloads)
      if (download.status == OfflineDownloadStatus.removing) ...[
        ...trackIdentityKeys(download.track),
        if (download.localTrackId?.trim() case final String id when id.isNotEmpty) id,
      ],
  };

  bool canRemove(Track track) => app.availableOfflineDownloadForTrack(track.id) != null;

  List<Track> removable(Iterable<Track> tracks) => tracks.where(canRemove).toList(growable: false);
}
