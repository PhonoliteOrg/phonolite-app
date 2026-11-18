import 'package:phonolite_app/data/models/collections/playlist.dart';

bool sameOfflinePlaylistSnapshots(List<Playlist> left, List<Playlist> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var i = 0; i < left.length; i += 1) {
    final a = left[i];
    final b = right[i];

    if (a.id != b.id ||
        a.name != b.name ||
        a.description != b.description ||
        a.imageRef != b.imageRef ||
        a.imagePath != b.imagePath ||
        a.pendingTrackSources.length != b.pendingTrackSources.length ||
        a.trackIds.length != b.trackIds.length) {
      return false;
    }

    for (var j = 0; j < a.pendingTrackSources.length; j += 1) {
      if (a.pendingTrackSources[j] != b.pendingTrackSources[j]) {
        return false;
      }
    }

    for (var j = 0; j < a.trackIds.length; j += 1) {
      if (a.trackIds[j] != b.trackIds[j]) {
        return false;
      }
    }
  }

  return true;
}
