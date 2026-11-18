import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/rules/downloads/offline_snapshot_comparison.dart';

bool sameLocalPlaylistEntries(List<LocalPlaylistEntry> left, List<LocalPlaylistEntry> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var i = 0; i < left.length; i++) {
    final a = left[i];
    final b = right[i];

    if (a.entryKey != b.entryKey ||
        a.status != b.status ||
        a.isPending != b.isPending ||
        a.localTrackId != b.localTrackId ||
        a.source != b.source ||
        a.error != b.error ||
        !sameOfflineTrackSnapshot(a.track, b.track)) {
      return false;
    }
  }

  return true;
}
