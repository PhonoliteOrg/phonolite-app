import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/track.dart';

/// The credit/profile portion of a track snapshot, shared by the download actor
/// and its UI receiver. Compare values directly: encoding entire biographies on
/// every progress update creates strings and garbage on the UI isolate.
bool sameTrackCreditMetadata(Track a, Track b) {
  return identical(a, b) ||
      (_sameList(a.artistIds, b.artistIds) &&
          _sameList(a.artistNames, b.artistNames) &&
          _sameList(a.artistCredits, b.artistCredits, _sameCredit) &&
          _sameAlbum(a.offlineAlbum, b.offlineAlbum) &&
          _sameArtist(a.offlineArtist, b.offlineArtist) &&
          _sameList(a.offlineArtists, b.offlineArtists, _sameArtist));
}

bool _sameList<T>(List<T> a, List<T> b, [bool Function(T, T)? same]) {
  if (identical(a, b)) {
    return true;
  }

  if (a.length != b.length) {
    return false;
  }

  for (var i = 0; i < a.length; i++) {
    if (identical(a[i], b[i])) {
      continue;
    }

    if (same != null ? !same(a[i], b[i]) : a[i] != b[i]) {
      return false;
    }
  }

  return true;
}

bool _sameCredit(ArtistCredit a, ArtistCredit b) {
  return a.artistId == b.artistId &&
      a.name == b.name &&
      a.creditedName == b.creditedName &&
      a.role == b.role &&
      a.joinPhrase == b.joinPhrase;
}

bool _sameArtist(Artist? a, Artist? b) {
  return identical(a, b) || (a != null && b != null && a.hasSameMetadata(b));
}

bool _sameAlbum(Album? a, Album? b) {
  if (identical(a, b)) {
    return true;
  }

  return a != null &&
      b != null &&
      a.id == b.id &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.artistId == b.artistId &&
      a.trackCount == b.trackCount &&
      a.year == b.year &&
      a.summary == b.summary &&
      _sameList(a.artistIds, b.artistIds) &&
      _sameList(a.artistNames, b.artistNames) &&
      _sameList(a.artistCredits, b.artistCredits, _sameCredit) &&
      _sameList(a.genres, b.genres);
}
