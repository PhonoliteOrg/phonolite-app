import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_track_genres.dart';

class OfflineAlbumGroup {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final List<Track> tracks;
  final String? coverPath;
  final Album? metadata;
  final List<ArtistCredit> artistCredits;

  const OfflineAlbumGroup({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.tracks,
    this.coverPath,
    this.metadata,
    this.artistCredits = const [],
  });

  Album toAlbum() {
    final stored = metadata;
    if (stored != null) {
      return stored.copyWith(
        trackCount: tracks.length,
        genres: stored.genres.isEmpty ? offlineTrackGenres(tracks) : stored.genres,
      );
    }

    return Album(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      artistCredits: artistCredits,
      trackCount: tracks.length,
      genres: offlineTrackGenres(tracks),
    );
  }
}
