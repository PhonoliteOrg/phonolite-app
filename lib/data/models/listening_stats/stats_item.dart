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
