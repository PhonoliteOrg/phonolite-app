import 'package:phonolite_app/data/models/listening_stats/stats_item.dart';
import 'package:phonolite_app/data/models/listening_stats/stats_track.dart';

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
