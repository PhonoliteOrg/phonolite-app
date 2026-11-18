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
