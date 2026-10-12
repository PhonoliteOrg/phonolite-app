import 'models.dart';

String offlineTrackSearchText(Track track) => [
  track.title,
  track.artist,
  track.album,
  for (final credit in [
    ...track.credits,
    ...track.offlineAlbum?.credits ?? const <ArtistCredit>[],
  ])
    '${credit.name} ${credit.displayName}',
].join(' ').toLowerCase();

class OfflineArtistGroup {
  const OfflineArtistGroup({
    required this.id,
    required this.name,
    required this.albums,
    this.coverPath,
    this.bannerPath,
    this.metadata,
  });

  final String id;
  final String name;
  final List<OfflineAlbumGroup> albums;
  final String? coverPath;
  final String? bannerPath;
  final Artist? metadata;

  List<OfflineAlbumGroup> get headlineAlbums => albums
      .where(
        (album) => album.toAlbum().credits.any(
          (credit) => credit.artistId == id && credit.isAlbumArtist,
        ),
      )
      .toList();

  List<OfflineAlbumGroup> get soloAlbums => headlineAlbums
      .where((album) => !album.toAlbum().isCollaboration)
      .toList();

  List<OfflineAlbumGroup> get collabAlbums {
    final soloIds = soloAlbums.map((album) => album.id).toSet();
    return headlineAlbums
        .where((album) => !soloIds.contains(album.id))
        .toList();
  }

  ArtistReleases get releases {
    final headlines = headlineAlbums;
    final headlineIds = headlines.map((album) => album.id).toSet();
    final appearances = <ArtistReleaseContribution>[];
    final other = <ArtistReleaseContribution>[];
    final collaborations = <ArtistReleaseContribution>[];
    final soloIds = soloAlbums.map((album) => album.id).toSet();
    for (final album in albums) {
      List<Track> songs(bool performing) => album.tracks
          .where(
            (track) => track.credits.any(
              (credit) =>
                  credit.artistId == id &&
                  credit.isPerformingArtist == performing,
            ),
          )
          .toList();
      ArtistReleaseContribution contribution(
        List<Track> matches,
        List<ArtistCredit> credits,
      ) => ArtistReleaseContribution(
        album: album.toAlbum(),
        trackIds: matches.map((track) => track.id).toList(),
        trackTitles: matches.map((track) => track.title).toList(),
        roles: credits.map((credit) => credit.role).toSet().toList(),
      );
      final performing = songs(true);
      final performingCredits = [
        for (final track in performing)
          ...track.credits.where(
            (credit) => credit.artistId == id && credit.isPerformingArtist,
          ),
      ];
      if (!headlineIds.contains(album.id) && performing.isNotEmpty) {
        appearances.add(contribution(performing, performingCredits));
      }
      final supporting = songs(false);
      final supportingCredits = [
        ...album.toAlbum().credits.where(
          (credit) =>
              credit.artistId == id &&
              !credit.isAlbumArtist &&
              !credit.isPerformingArtist,
        ),
        for (final track in supporting)
          ...track.credits.where(
            (credit) => credit.artistId == id && !credit.isPerformingArtist,
          ),
      ];
      if (supportingCredits.isNotEmpty) {
        other.add(contribution(supporting, supportingCredits));
      }
      if (headlineIds.contains(album.id) && !soloIds.contains(album.id)) {
        final matches = album.tracks;
        final credits = [
          ...album.toAlbum().credits.where(
            (credit) => credit.artistId == id && credit.isAlbumArtist,
          ),
        ];
        collaborations.add(contribution(matches, credits));
      }
    }
    return ArtistReleases(
      albums: soloAlbums.map((album) => album.toAlbum()).toList(),
      collabAlbums: collaborations,
      appearsOn: appearances,
      otherCredits: other,
    );
  }

  List<Track> get tracksForArtist {
    final headlineIds = headlineAlbums.map((album) => album.id).toSet();
    return [
      for (final album in albums)
        for (final track in album.tracks)
          if (headlineIds.contains(album.id) ||
              track.credits.any(
                (credit) => credit.artistId == id && credit.isPerformingArtist,
              ))
            track,
    ];
  }

  int get trackCount => tracksForArtist.length;

  Artist toArtist() {
    final stored = metadata;
    if (stored != null) {
      return Artist(
        id: stored.id,
        name: stored.name,
        albumCount: soloAlbums.length,
        collabAlbumCount: collabAlbums.length,
        appearanceCount: releases.appearsOn.length,
        otherCreditCount: releases.otherCredits.length,
        releaseCount: releases.releaseCount,
        genres: stored.genres.isEmpty
            ? _trackGenres(tracksForArtist)
            : stored.genres,
        summary: stored.summary,
        logoRef: stored.logoRef,
        bannerRef: stored.bannerRef,
      );
    }
    final albumLabel = albums.length == 1 ? 'album' : 'albums';
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';
    return Artist(
      id: id,
      name: name,
      albumCount: soloAlbums.length,
      collabAlbumCount: collabAlbums.length,
      appearanceCount: releases.appearsOn.length,
      otherCreditCount: releases.otherCredits.length,
      releaseCount: releases.releaseCount,
      genres: _trackGenres(tracksForArtist),
      summary:
          '${albums.length} downloaded $albumLabel / '
          '$trackCount downloaded $trackLabel.',
    );
  }
}

class OfflineAlbumGroup {
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

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final List<Track> tracks;
  final String? coverPath;
  final Album? metadata;
  final List<ArtistCredit> artistCredits;

  Album toAlbum() {
    final stored = metadata;
    if (stored != null) {
      return stored.copyWith(
        trackCount: tracks.length,
        genres: stored.genres.isEmpty ? _trackGenres(tracks) : stored.genres,
      );
    }
    return Album(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      artistCredits: artistCredits,
      trackCount: tracks.length,
      genres: _trackGenres(tracks),
    );
  }
}

List<OfflineArtistGroup> offlineArtistGroups(
  List<Track> tracks, {
  bool includeContributors = false,
}) {
  final artistBuilders = <String, _OfflineArtistBuilder>{};
  final albumBuilders = <String, _OfflineAlbumBuilder>{};
  for (final track in tracks) {
    final albumMetadata = track.offlineAlbum;
    final albumTitle = _displayName(
      albumMetadata?.title ?? track.album,
      fallback: 'Unknown Album',
    );
    final primaryId =
        _nonEmpty(albumMetadata?.artistId) ??
        _nonEmpty(track.artistId) ??
        _normalizedGroupKey(track.artist);
    final primaryName = _displayName(
      albumMetadata?.artist ?? track.artist,
      fallback: 'Unknown Artist',
    );
    final fallbackCredits = track.credits
        .where((credit) => credit.isAlbumArtist)
        .toList();
    final albumCredits =
        albumMetadata?.credits ??
        (fallbackCredits.isNotEmpty
            ? fallbackCredits
            : [
                ArtistCredit(
                  artistId: primaryId,
                  name:
                      track.credits
                          .where((credit) => credit.artistId == primaryId)
                          .map((credit) => credit.name)
                          .firstOrNull ??
                      primaryName,
                ),
              ]);
    final albumId =
        _nonEmpty(albumMetadata?.id) ??
        _nonEmpty(track.albumId) ??
        '$primaryId::${_normalizedGroupKey(albumTitle)}';
    // Every contributor points at the same album and downloaded song list.
    final albumBuilder = albumBuilders.putIfAbsent(
      albumId,
      () => _OfflineAlbumBuilder(
        id: albumId,
        title: albumTitle,
        artist: primaryName,
        artistId: primaryId,
        metadata: albumMetadata,
        artistCredits: albumCredits,
      ),
    );
    albumBuilder.metadata ??= albumMetadata;
    albumBuilder.coverPath ??= _nonEmpty(track.albumArtPath);
    albumBuilder.tracks.add(track);
    final credits = <String, ArtistCredit>{
      for (final credit in [...albumCredits, ...track.credits])
        if (credit.artistId.isNotEmpty) credit.artistId: credit,
    };
    if (credits.isEmpty) {
      credits[primaryId] = ArtistCredit(artistId: primaryId, name: primaryName);
    }
    for (final credit in credits.values) {
      final artistMetadata = [
        ...track.offlineArtists,
        if (track.offlineArtist != null) track.offlineArtist!,
      ].where((artist) => artist.id == credit.artistId).firstOrNull;
      final artistBuilder = artistBuilders.putIfAbsent(
        credit.artistId,
        () => _OfflineArtistBuilder(
          id: credit.artistId,
          name: _displayName(
            artistMetadata?.name ?? credit.name,
            fallback: 'Unknown Artist',
          ),
          metadata: artistMetadata,
        ),
      );
      artistBuilder.metadata ??= artistMetadata;
      artistBuilder.isBilled |= [...albumCredits, ...track.credits].any(
        (candidate) =>
            candidate.artistId == credit.artistId &&
            candidate.isPerformingArtist,
      );
      if (track.artistId == credit.artistId ||
          track.offlineArtist?.id == credit.artistId) {
        artistBuilder.coverPath ??= _nonEmpty(track.artistArtPath);
        artistBuilder.bannerPath ??= _nonEmpty(track.artistBannerPath);
      }
      artistBuilder.albums[albumId] = albumBuilder;
    }
  }
  final artists =
      artistBuilders.values
          .where((artist) => includeContributors || artist.isBilled)
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    for (final artist in artists)
      OfflineArtistGroup(
        id: artist.id,
        name: artist.metadata?.name ?? artist.name,
        coverPath: artist.coverPath,
        bannerPath: artist.bannerPath,
        metadata: artist.metadata,
        albums: _sortedAlbums(artist),
      ),
  ];
}

List<OfflineAlbumGroup> _sortedAlbums(_OfflineArtistBuilder artist) {
  final albums = artist.albums.values.toList(growable: false)
    ..sort(_compareOfflineAlbumsByReleaseYear);
  return [
    for (final album in albums)
      OfflineAlbumGroup(
        id: album.id,
        title: album.title,
        artist: album.artist,
        artistId: album.artistId,
        coverPath: album.coverPath,
        metadata: album.metadata,
        artistCredits: album.artistCredits,
        tracks: List<Track>.from(album.tracks)..sort(_compareOfflineTracks),
      ),
  ];
}

int _compareOfflineAlbumsByReleaseYear(
  _OfflineAlbumBuilder a,
  _OfflineAlbumBuilder b,
) {
  final aYear = a.metadata?.year;
  final bYear = b.metadata?.year;
  if (aYear != null && bYear != null) {
    final year = aYear.compareTo(bYear);
    if (year != 0) {
      return year;
    }
  } else if (aYear != null) {
    return -1;
  } else if (bYear != null) {
    return 1;
  }

  final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (title != 0) {
    return title;
  }
  return a.id.compareTo(b.id);
}

int _compareOfflineTracks(Track a, Track b) {
  final disc = (a.discNo ?? 0).compareTo(b.discNo ?? 0);
  if (disc != 0) {
    return disc;
  }
  final track = (a.trackNo ?? 0).compareTo(b.trackNo ?? 0);
  if (track != 0) {
    return track;
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

String _normalizedGroupKey(String name) {
  return name.trim().toLowerCase();
}

String _displayName(String value, {required String fallback}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _trackGenres(Iterable<Track> tracks) {
  final genres = <String>[];
  final seen = <String>{};
  for (final track in tracks) {
    for (final raw in track.genres) {
      final genre = raw.trim();
      if (genre.isEmpty) {
        continue;
      }
      if (seen.add(genre.toLowerCase())) {
        genres.add(genre);
      }
    }
  }
  return List.unmodifiable(genres);
}

class _OfflineArtistBuilder {
  _OfflineArtistBuilder({required this.id, required this.name, this.metadata});

  final String id;
  final String name;
  Artist? metadata;
  bool isBilled = false;
  String? coverPath;
  String? bannerPath;
  final Map<String, _OfflineAlbumBuilder> albums =
      <String, _OfflineAlbumBuilder>{};
}

class _OfflineAlbumBuilder {
  _OfflineAlbumBuilder({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    this.metadata,
    required this.artistCredits,
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  Album? metadata;
  final List<ArtistCredit> artistCredits;
  String? coverPath;
  final List<Track> tracks = <Track>[];
}
