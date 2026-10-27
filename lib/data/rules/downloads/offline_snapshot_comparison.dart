import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
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
