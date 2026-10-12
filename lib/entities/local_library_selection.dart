import 'models.dart';
import 'offline_library_views.dart';

/// Queries a local library snapshot without knowing about storage or playback.
/// Identity matching intentionally accepts local and server aliases; persisted
/// source reconciliation remains the storage layer's responsibility.
class LocalLibrarySelection {
  const LocalLibrarySelection({
    required Iterable<Track> tracks,
    required Iterable<OfflineArtistGroup> artists,
  }) : _tracks = tracks,
       _artists = artists;

  final Iterable<Track> _tracks;
  final Iterable<OfflineArtistGroup> _artists;

  OfflineArtistGroup? artist(String artistId) {
    final target = artistId.trim();
    if (target.isEmpty) {
      return null;
    }
    for (final group in _artists) {
      if (group.id == target) {
        return group;
      }
    }
    return null;
  }

  OfflineAlbumGroup? album(String albumId) {
    final target = albumId.trim();
    if (target.isEmpty) {
      return null;
    }
    for (final artist in _artists) {
      for (final album in artist.albums) {
        if (album.id == target) {
          return album;
        }
      }
    }
    return null;
  }

  OfflineArtistGroup? artistForTrackId(String? trackId) {
    final selected = track(trackId);
    if (selected == null) {
      return null;
    }
    return artistForTrack(selected);
  }

  OfflineAlbumGroup? albumForTrackId(String? trackId) {
    final selected = track(trackId);
    if (selected == null) {
      return null;
    }
    return albumForTrack(selected);
  }

  OfflineArtistGroup? artistForTrack(Track track) {
    final primary = track.artistId;
    if (primary != null) {
      final identified = artist(primary);
      if (identified != null &&
          identified.tracksForArtist.any(
            (candidate) => _sameLocalTrack(candidate, track),
          )) {
        return identified;
      }
    }
    for (final group in _artists) {
      if (group.tracksForArtist.any(
        (candidate) => _sameLocalTrack(candidate, track),
      )) {
        return group;
      }
    }
    return null;
  }

  OfflineAlbumGroup? albumForTrack(Track track) {
    for (final group in _artists) {
      for (final album in group.albums) {
        if (album.tracks.any(
          (candidate) => _sameLocalTrack(candidate, track),
        )) {
          return album;
        }
      }
    }
    return null;
  }

  Track? track(String? trackId) {
    final target = trackId?.trim();
    if (target == null || target.isEmpty) {
      return null;
    }
    for (final track in _tracks) {
      if (_localTrackMatchesId(track, target)) {
        return track;
      }
    }
    return null;
  }

  bool _sameLocalTrack(Track left, Track right) {
    final leftIds = _localTrackIdentityValues(left).toSet();
    for (final id in _localTrackIdentityValues(right)) {
      if (leftIds.contains(id)) {
        return true;
      }
    }
    return false;
  }

  bool _localTrackMatchesId(Track track, String trackId) {
    return _localTrackIdentityValues(track).contains(trackId);
  }

  Iterable<String> _localTrackIdentityValues(Track track) sync* {
    for (final value in <String?>[
      track.id,
      track.localId,
      track.serverTrackId,
    ]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  bool matchesCustomShuffle(
    Track track, {
    required Set<String> artistIds,
    required Set<String> genres,
  }) {
    if (artistIds.isNotEmpty) {
      final group = artistForTrack(track);
      final ids = <String>{
        ...track.credits
            .where((credit) => credit.isPerformingArtist)
            .map((credit) => credit.artistId),
        ...track.offlineAlbum?.credits
                .where((credit) => credit.isAlbumArtist)
                .map((credit) => credit.artistId) ??
            const <String>[],
        if (group != null) group.id,
        if (track.artistId != null && track.artistId!.isNotEmpty)
          track.artistId!,
        if (track.offlineArtist?.id.isNotEmpty ?? false)
          track.offlineArtist!.id,
      };
      if (ids.any(artistIds.contains)) {
        return true;
      }
    }
    if (genres.isNotEmpty) {
      return _localTrackGenres(track).any(genres.contains);
    }
    return false;
  }

  Set<String> _localTrackGenres(Track track) {
    final values = <String>{};
    void addAll(Iterable<String> genres) {
      for (final genre in genres) {
        final normalized = genre.trim().toLowerCase();
        if (normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    }

    addAll(track.genres);
    addAll(track.offlineAlbum?.genres ?? const <String>[]);
    addAll(track.offlineArtist?.genres ?? const <String>[]);
    final contributorIds = <String>{
      ...track.credits
          .where((credit) => credit.isPerformingArtist)
          .map((credit) => credit.artistId),
      ...track.offlineAlbum?.credits
              .where((credit) => credit.isAlbumArtist)
              .map((credit) => credit.artistId) ??
          const <String>[],
      if (track.artistId != null) track.artistId!,
      if (track.offlineArtist != null) track.offlineArtist!.id,
    };
    for (final artist in track.offlineArtists) {
      if (contributorIds.contains(artist.id)) addAll(artist.genres);
    }
    return values;
  }
}
