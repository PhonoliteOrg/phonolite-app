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
  final List<StatsItem> topArtists;
  final List<StatsTrack> topTracks;
  final List<StatsItem> topGenres;

  factory StatsResponse.fromJson(Map<String, dynamic> json) {
    return StatsResponse(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt(),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      topArtists: (json['top_artists'] as List?)
              ?.map(StatsItem.parse)
              .toList() ??
          <StatsItem>[],
      topTracks: (json['top_tracks'] as List?)
              ?.map(StatsTrack.parse)
              .toList() ??
          <StatsTrack>[],
      topGenres: (json['top_genres'] as List?)
              ?.map(StatsItem.parse)
              .toList() ??
          <StatsItem>[],
    );
  }
}

class StatsItem {
  StatsItem({
    required this.id,
    required this.name,
    required this.minutes,
  });

  final String id;
  final String name;
  final int minutes;

  factory StatsItem.fromJson(Map<String, dynamic> json) {
    return StatsItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  static StatsItem parse(dynamic item) {
    if (item is Map) {
      return StatsItem.fromJson(Map<String, dynamic>.from(item));
    }
    final text = item?.toString() ?? '';
    return StatsItem(id: text, name: text, minutes: 0);
  }
}

class StatsTrack {
  StatsTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.minutes,
    required this.plays,
  });

  final String id;
  final String title;
  final String artist;
  final int minutes;
  final int plays;

  factory StatsTrack.fromJson(Map<String, dynamic> json) {
    return StatsTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      plays: (json['plays'] as num?)?.toInt() ?? 0,
    );
  }

  static StatsTrack parse(dynamic item) {
    if (item is Map) {
      return StatsTrack.fromJson(Map<String, dynamic>.from(item));
    }
    final text = item?.toString() ?? '';
    return StatsTrack(
      id: '',
      title: text,
      artist: '',
      minutes: 0,
      plays: 0,
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
