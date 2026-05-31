import 'models.dart';

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

  int get trackCount =>
      albums.fold(0, (total, album) => total + album.tracks.length);

  Artist toArtist() {
    final stored = metadata;
    if (stored != null) {
      return Artist(
        id: stored.id,
        name: stored.name,
        albumCount: albums.length,
        genres: stored.genres.isEmpty
            ? _artistTrackGenres(albums)
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
      albumCount: albums.length,
      genres: _artistTrackGenres(albums),
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
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final List<Track> tracks;
  final String? coverPath;
  final Album? metadata;

  Album toAlbum() {
    final stored = metadata;
    if (stored != null) {
      return Album(
        id: stored.id,
        title: stored.title,
        artist: stored.artist,
        artistId: stored.artistId,
        trackCount: tracks.length,
        year: stored.year,
        genres: stored.genres.isEmpty ? _trackGenres(tracks) : stored.genres,
        summary: stored.summary,
      );
    }
    return Album(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      trackCount: tracks.length,
      genres: _trackGenres(tracks),
    );
  }
}

List<OfflineArtistGroup> offlineArtistGroups(List<Track> tracks) {
  final artistBuilders = <String, _OfflineArtistBuilder>{};
  for (final track in tracks) {
    final artistMetadata = track.offlineArtist;
    final artistName = _displayName(
      artistMetadata?.name ?? track.artist,
      fallback: 'Unknown Artist',
    );
    final artistKey =
        _nonEmpty(artistMetadata?.id) ??
        _nonEmpty(track.artistId) ??
        _normalizedGroupKey(artistName);
    final artistBuilder = artistBuilders.putIfAbsent(
      artistKey,
      () => _OfflineArtistBuilder(
        id: artistKey,
        name: artistName,
        metadata: artistMetadata,
      ),
    );
    artistBuilder.metadata ??= artistMetadata;
    artistBuilder.coverPath ??= _nonEmpty(track.artistArtPath);
    artistBuilder.bannerPath ??= _nonEmpty(track.artistBannerPath);
    final albumMetadata = track.offlineAlbum;
    final albumTitle = _displayName(
      albumMetadata?.title ?? track.album,
      fallback: 'Unknown Album',
    );
    final albumKey =
        _nonEmpty(albumMetadata?.id) ??
        _nonEmpty(track.albumId) ??
        _normalizedGroupKey(albumTitle);
    final albumId = _nonEmpty(albumMetadata?.id) ?? '$artistKey::$albumKey';
    final albumBuilder = artistBuilder.albums.putIfAbsent(
      albumKey,
      () => _OfflineAlbumBuilder(
        id: albumId,
        title: albumTitle,
        artist: albumMetadata?.artist ?? artistBuilder.name,
        artistId: albumMetadata?.artistId ?? artistBuilder.id,
        metadata: albumMetadata,
      ),
    );
    albumBuilder.metadata ??= albumMetadata;
    albumBuilder.coverPath ??= _nonEmpty(track.albumArtPath);
    albumBuilder.tracks.add(track);
  }

  final artists = artistBuilders.values.toList(growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    for (final artist in artists)
      OfflineArtistGroup(
        id: artist.id,
        name: artist.name,
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

List<String> _artistTrackGenres(List<OfflineAlbumGroup> albums) {
  return _trackGenres([for (final album in albums) ...album.tracks]);
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
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  Album? metadata;
  String? coverPath;
  final List<Track> tracks = <Track>[];
}
