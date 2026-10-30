import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/queries/library/library_search_matcher.dart';

export 'package:phonolite_app/data/queries/library/library_search_matcher.dart';

/// Uses the server's fuzzy scores and ordering, limiting only after ranking.
/// Artists and shared albums come from the complete downloaded catalog, so an
/// album is returned once even when it is billed to several artists.
List<SearchResult> searchLocalLibrary({
  required String query,
  required List<Track> tracks,
  required List<OfflineArtistGroup> artists,
  int limit = 50,
}) {
  final matcher = LibrarySearchQuery(query);

  if (matcher.isEmpty) {
    return [];
  }

  limit = limit.clamp(1, 100);
  final results = <SearchResult>[];

  void collect(List<({String key, SearchResult result})> candidates) {
    // Nonmatches never participate in ranking or its catalogue-order ties.
    // Remove them before sorting the candidate list, which can be much larger
    // than the few results returned for a query.
    candidates.removeWhere((candidate) => candidate.result.score! <= 0);
    candidates.sort((a, b) => _compareSearchText(a.key, b.key));
    results.addAll(candidates.map((candidate) => candidate.result));
  }

  collect([
    for (final artist in artists)
      (
        key: '${artist.name.trim().toLowerCase()}\x1f${artist.id}',
        result: SearchResult(
          kind: 'artist',
          id: artist.id,
          title: artist.name,
          artworkPath: artist.coverPath,
          score: matcher.score(artist.name),
        ),
      ),
  ]);

  final albums = <String, OfflineAlbumGroup>{
    for (final artist in artists)
      for (final album in artist.albums) album.id: album,
  };
  final trackAlbums = <String, OfflineAlbumGroup>{
    for (final album in albums.values)
      for (final track in album.tracks) track.id: album,
  };

  collect([
    for (final group in albums.values)
      (
        key: _albumSearchKey(group),
        result: SearchResult(
          kind: 'album',
          id: group.id,
          title: group.title,
          subtitle: group.artist,
          albumId: group.id,
          artworkPath: group.coverPath,
          score: _albumSearchScore(matcher, group),
        ),
      ),
  ]);

  collect([
    for (final track in <String, Track>{for (final track in tracks) track.id: track}.values)
      (
        key: _trackSearchKey(track),
        result: SearchResult(
          kind: 'track',
          id: track.id,
          title: track.title,
          subtitle: '${track.artist} - ${track.album}',
          albumId: trackAlbums[track.id]?.id ?? track.albumId,
          artworkPath: trackAlbums[track.id]?.coverPath ?? track.albumArtPath,
          score: _trackSearchScore(matcher, track),
        ),
      ),
  ]);

  // Rust's stable sort preserves catalog order when both score and title tie.
  final ranked = [for (final (index, result) in results.indexed) (catalogIndex: index, result: result)];

  ranked.sort((a, b) {
    final score = b.result.score!.compareTo(a.result.score!);

    if (score != 0) {
      return score;
    }

    final title = _compareSearchText(a.result.title, b.result.title);

    return title != 0 ? title : a.catalogIndex.compareTo(b.catalogIndex);
  });

  return ranked.take(limit).map((entry) => entry.result).toList(growable: false);
}

String _albumSearchKey(OfflineAlbumGroup group) {
  final album = group.toAlbum();
  final year = (album.year ?? 9999).clamp(0, 9999).toString().padLeft(4, '0');

  return '${_albumSearchArtist(group).toLowerCase()}\x1f$year\x1f'
      '${album.title.toLowerCase()}\x1f${album.id}';
}

String _albumSearchArtist(OfflineAlbumGroup group) {
  final album = group.toAlbum();
  final names = album.artistNames.isNotEmpty
      ? album.artistNames
      : album.credits.where((credit) => credit.isAlbumArtist).map((c) => c.name);

  return names.join(' ').trim();
}

String _trackSearchKey(Track track) {
  final artist = _trackSearchArtist(track).toLowerCase();
  final disc = (track.discNo ?? 65535).toString().padLeft(5, '0');
  final number = (track.trackNo ?? 65535).toString().padLeft(5, '0');

  return '$artist\x1f${track.album.toLowerCase()}\x1f$disc\x1f$number\x1f'
      '${track.title.toLowerCase()}\x1f${track.id}';
}

String _trackSearchArtist(Track track) {
  final displayed = track.artist.toLowerCase();
  final names = track.credits
      .where((credit) => credit.isPerformingArtist)
      .where((credit) => !displayed.contains(credit.name.toLowerCase()))
      .map((credit) => credit.name)
      .join(' ');

  return '${track.artist} $names'.trim();
}

int _albumSearchScore(LibrarySearchQuery matcher, OfflineAlbumGroup group) {
  final catalogScore = matcher.score('${group.title} ${_albumSearchArtist(group)}');
  final displayScore = matcher.score('${group.title} ${group.artist}');

  return catalogScore > displayScore ? catalogScore : displayScore;
}

int _trackSearchScore(LibrarySearchQuery matcher, Track track) {
  final artist = _trackSearchArtist(track);
  final catalogScore = matcher.score('${track.title} $artist ${track.album}');

  if (artist == track.artist) {
    return catalogScore;
  }

  final displayScore = matcher.score('${track.title} ${track.artist} ${track.album}');

  return catalogScore > displayScore ? catalogScore : displayScore;
}

// Compare Unicode scalar values, matching Rust's UTF-8 string ordering.
int _compareSearchText(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;

  while (left.moveNext()) {
    if (!right.moveNext()) {
      return 1;
    }

    final order = left.current.compareTo(right.current);

    if (order != 0) {
      return order;
    }
  }

  return right.moveNext() ? -1 : 0;
}
