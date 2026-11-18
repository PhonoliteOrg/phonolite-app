import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/offline_metadata_comparison.dart';

bool sameOfflineTrackSnapshots(List<Track> left, List<Track> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var i = 0; i < left.length; i += 1) {
    if (!sameOfflineTrackSnapshot(left[i], right[i])) {
      return false;
    }
  }

  return true;
}

bool sameOfflineTrackSnapshot(Track a, Track b) {
  return a.id == b.id &&
      a.localId == b.localId &&
      a.serverBaseUrl == b.serverBaseUrl &&
      a.serverTrackId == b.serverTrackId &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.artistId == b.artistId &&
      sameTrackCreditMetadata(a, b) &&
      a.album == b.album &&
      a.albumId == b.albumId &&
      a.durationMs == b.durationMs &&
      a.liked == b.liked &&
      a.inPlaylists == b.inPlaylists &&
      a.albumArtPath == b.albumArtPath &&
      a.artistArtPath == b.artistArtPath &&
      a.artistBannerPath == b.artistBannerPath;
}
