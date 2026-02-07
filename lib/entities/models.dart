class Artist {
  Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    this.genres = const [],
    this.summary,
    this.logoRef,
    this.bannerRef,
  });

  final String id;
  final String name;
  final int albumCount;
  final List<String> genres;
  final String? summary;
  final String? logoRef;
  final String? bannerRef;

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      albumCount: (json['album_count'] as num?)?.toInt() ?? 0,
      genres: (json['genres'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      summary: json['summary'] as String?,
      logoRef: json['logo_ref'] as String?,
      bannerRef: json['banner_ref'] as String?,
    );
  }
}

class Album {
  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.trackCount,
    this.year,
    this.genres = const [],
    this.summary,
  });

  final String id;
  final String title;
  final String artist;
  final String artistId;
  final int trackCount;
  final int? year;
  final List<String> genres;
  final String? summary;

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      artistId: json['artist_id'] as String? ?? '',
      trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt(),
      genres: (json['genres'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      summary: json['summary'] as String?,
    );
  }
}

class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.liked,
    required this.inPlaylists,
    this.albumId,
    this.trackNo,
    this.discNo,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final int durationMs;
  final bool liked;
  final bool inPlaylists;
  final int? trackNo;
  final int? discNo;

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      albumId: json['album_id'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      liked: json['liked'] as bool? ?? false,
      inPlaylists: json['in_playlists'] as bool? ?? false,
      trackNo: (json['track_no'] as num?)?.toInt(),
      discNo: (json['disc_no'] as num?)?.toInt(),
    );
  }

  Track copyWith({bool? liked, bool? inPlaylists}) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      liked: liked ?? this.liked,
      inPlaylists: inPlaylists ?? this.inPlaylists,
      albumId: albumId,
      trackNo: trackNo,
      discNo: discNo,
    );
  }
}

class Playlist {
  Playlist({required this.id, required this.name, required this.trackIds});

  final String id;
  final String name;
  final List<String> trackIds;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final ids = (json['track_ids'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        <String>[];
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackIds: ids,
    );
  }
}

class StatsResponse {
  StatsResponse({
    required this.year,
    required this.month,
    required this.totalMinutes,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
  });

  final int year;
  final int? month;
  final int totalMinutes;
  final List<String> topArtists;
  final List<String> topTracks;
  final List<String> topGenres;

  factory StatsResponse.fromJson(Map<String, dynamic> json) {
    return StatsResponse(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt(),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      topArtists: (json['top_artists'] as List?)
              ?.map((item) => item['name']?.toString() ?? item.toString())
              .toList() ??
          <String>[],
      topTracks: (json['top_tracks'] as List?)
              ?.map((item) => item['title']?.toString() ?? item.toString())
              .toList() ??
          <String>[],
      topGenres: (json['top_genres'] as List?)
              ?.map((item) => item['name']?.toString() ?? item.toString())
              .toList() ??
          <String>[],
    );
  }
}

class SearchResult {
  SearchResult({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
  });

  final String kind;
  final String id;
  final String title;
  final String? subtitle;
  final int? score;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      kind: json['kind'] as String? ?? 'track',
      id: json['id'] as String,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? json['artist'] as String?,
      score: (json['score'] as num?)?.toInt(),
    );
  }
}

class PlayerQueueResponse {
  PlayerQueueResponse({
    required this.track,
    required this.index,
    required this.total,
    required this.ended,
  });

  final Track? track;
  final int index;
  final int total;
  final bool ended;

  factory PlayerQueueResponse.fromJson(Map<String, dynamic> json) {
    return PlayerQueueResponse(
      track: json['track'] == null
          ? null
          : Track.fromJson(json['track'] as Map<String, dynamic>),
      index: (json['index'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      ended: json['ended'] as bool? ?? false,
    );
  }
}

class OutputDevice {
  OutputDevice({required this.id, required this.name});

  final int id;
  final String name;
}
