import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

class ArtistReleaseContribution {
  final Album album;
  final List<String> trackIds;
  final List<String> trackTitles;
  final List<String> roles;

  const ArtistReleaseContribution({
    required this.album,
    this.trackIds = const [],
    this.trackTitles = const [],
    this.roles = const [],
  });

  factory ArtistReleaseContribution.fromJson(Map<String, dynamic> json) => ArtistReleaseContribution(
    album: Album.fromJson(Map<String, dynamic>.from(json['album'] as Map)),
    trackIds: JsonValues.strings(json['track_ids']),
    trackTitles: JsonValues.strings(json['track_titles']),
    roles: JsonValues.strings(json['roles']),
  );

  bool get isAlbumArtist => roles.any(ArtistCredit.isAlbumArtistRole);

  bool get isPerformingArtist => roles.any(ArtistCredit.isPerformingArtistRole);
}

class ArtistReleases {
  final List<Album> _albums;
  final List<ArtistReleaseContribution> _collabAlbums;
  final List<ArtistReleaseContribution> _appearsOn;
  final List<ArtistReleaseContribution> _otherCredits;

  const ArtistReleases({
    List<Album> albums = const [],
    List<ArtistReleaseContribution> collabAlbums = const [],
    List<ArtistReleaseContribution> appearsOn = const [],
    List<ArtistReleaseContribution> otherCredits = const [],
  }) : _albums = albums,
       _collabAlbums = collabAlbums,
       _appearsOn = appearsOn,
       _otherCredits = otherCredits;

  factory ArtistReleases.fromJson(Map<String, dynamic> json) => ArtistReleases(
    albums: [
      for (final item in json['albums'] as List? ?? const []) Album.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    collabAlbums: [
      for (final item in json['collab_albums'] as List? ?? const [])
        ArtistReleaseContribution.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    appearsOn: [
      for (final item in json['appears_on'] as List? ?? const [])
        ArtistReleaseContribution.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    otherCredits: [
      for (final item in json['other_credits'] as List? ?? const [])
        ArtistReleaseContribution.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
  );

  List<Album> get albums => _albums.where((album) => !album.isCollaboration).toList();

  List<ArtistReleaseContribution> get collabAlbums {
    final soloIds = albums.map((album) => album.id).toSet();

    return _mergeReleaseContributions(
      [
        ..._collabAlbums.where((entry) => entry.isAlbumArtist),
        for (final album in _albums)
          if (album.isCollaboration)
            ArtistReleaseContribution(
              album: album,
              roles: album.credits
                  .where((credit) => credit.isAlbumArtist)
                  .map((credit) => credit.role)
                  .toSet()
                  .toList(),
            ),
      ].where((entry) => !soloIds.contains(entry.album.id)),
    );
  }

  List<Album> get headlineAlbums => <String, Album>{
    for (final album in albums) album.id: album,
    for (final entry in collabAlbums)
      if (entry.isAlbumArtist) entry.album.id: entry.album,
  }.values.toList();

  // Older servers put song guests and supporting roles in collab_albums.
  // Recover their song scope without presenting them as joint album artists.
  List<ArtistReleaseContribution> get appearsOn => _mergeReleaseContributions([
    ..._appearsOn,
    for (final entry in _collabAlbums)
      if (!entry.isAlbumArtist &&
          entry.isPerformingArtist &&
          !_appearsOn.any((appearance) => appearance.album.id == entry.album.id))
        ArtistReleaseContribution(
          album: entry.album,
          trackIds: entry.trackIds,
          trackTitles: entry.trackTitles,
          roles: entry.roles.where(ArtistCredit.isGuestArtistRole).toList(),
        ),
  ]);

  List<ArtistReleaseContribution> get otherCredits {
    // Older servers can repeat headline releases for their supporting roles.
    final headlineIds = headlineAlbums.map((album) => album.id).toSet();

    return _mergeReleaseContributions(
      [
        ..._otherCredits,
        ..._collabAlbums.where(
          (entry) => !entry.isPerformingArtist && !_otherCredits.any((credit) => credit.album.id == entry.album.id),
        ),
      ].where((entry) => !headlineIds.contains(entry.album.id)),
    );
  }

  int get releaseCount => {
    for (final album in _albums) album.id,
    for (final entry in collabAlbums) entry.album.id,
    for (final entry in appearsOn) entry.album.id,
  }.length;
}

List<ArtistReleaseContribution> _mergeReleaseContributions(Iterable<ArtistReleaseContribution> entries) {
  final byAlbum = <String, ArtistReleaseContribution>{};

  for (final entry in entries) {
    final previous = byAlbum[entry.album.id];

    if (previous == null) {
      byAlbum[entry.album.id] = entry;
      continue;
    }

    final titles = <String, String>{};

    for (final contribution in [previous, entry]) {
      for (var index = 0; index < contribution.trackIds.length; index++) {
        final id = contribution.trackIds[index];
        final title = index < contribution.trackTitles.length ? contribution.trackTitles[index] : '';

        if (titles[id]?.isNotEmpty != true) {
          titles[id] = title;
        }
      }
    }

    byAlbum[entry.album.id] = ArtistReleaseContribution(
      album: previous.album,
      trackIds: titles.keys.toList(),
      trackTitles: titles.values.toList(),
      roles: {...previous.roles, ...entry.roles}.toList(),
    );
  }

  return byAlbum.values.toList();
}
