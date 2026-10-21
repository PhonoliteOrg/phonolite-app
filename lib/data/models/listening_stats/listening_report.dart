class StatsResponse {
  final int year;
  final int? month;
  final int totalMinutes;
  final int totalListeningMs;
  final int totalPlays;
  final int uniqueTracks;
  final int uniqueArtists;
  final int otherGenreListeningMs;
  final int unclassifiedListeningMs;
  final List<StatsItem> topArtists;
  final List<StatsTrack> topTracks;
  final List<StatsItem> topGenres;

  StatsResponse({
    required this.year,
    required this.month,
    required this.totalMinutes,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
    this.totalListeningMs = 0,
    this.totalPlays = 0,
    this.uniqueTracks = 0,
    this.uniqueArtists = 0,
    this.otherGenreListeningMs = 0,
    this.unclassifiedListeningMs = 0,
  });

  factory StatsResponse.fromJson(Map<String, dynamic> json) {
    return StatsResponse(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt(),
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      totalListeningMs:
          (json['total_listening_ms'] as num?)?.toInt() ?? ((json['total_minutes'] as num?)?.toInt() ?? 0) * 60000,
      totalPlays: (json['total_plays'] as num?)?.toInt() ?? 0,
      uniqueTracks: (json['unique_tracks'] as num?)?.toInt() ?? 0,
      uniqueArtists: (json['unique_artists'] as num?)?.toInt() ?? 0,
      otherGenreListeningMs: (json['other_genre_listening_ms'] as num?)?.toInt() ?? 0,
      unclassifiedListeningMs: (json['unclassified_listening_ms'] as num?)?.toInt() ?? 0,
      topArtists: (json['top_artists'] as List?)?.map(StatsItem.parse).toList() ?? <StatsItem>[],
      topTracks: (json['top_tracks'] as List?)?.map(StatsTrack.parse).toList() ?? <StatsTrack>[],
      topGenres: (json['top_genres'] as List?)?.map(StatsItem.parse).toList() ?? <StatsItem>[],
    );
  }
}

class StatsItem {
  final String id;
  final String name;
  final int minutes;
  final int listeningMs;

  StatsItem({required this.id, required this.name, required this.minutes, int? listeningMs})
    : listeningMs = listeningMs ?? minutes * 60000;

  factory StatsItem.fromJson(Map<String, dynamic> json) {
    return StatsItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      listeningMs: (json['listening_ms'] as num?)?.toInt(),
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
  final String id;
  final String title;
  final String artist;
  final int minutes;
  final int plays;

  StatsTrack({required this.id, required this.title, required this.artist, required this.minutes, required this.plays});

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

    return StatsTrack(id: '', title: text, artist: '', minutes: 0, plays: 0);
  }
}
