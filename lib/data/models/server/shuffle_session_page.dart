import 'package:phonolite_app/data/models/library/track.dart';

class ShuffleSessionPage {
  final String sessionId;
  final int offset;
  final int nextOffset;
  final int total;
  final bool hasMore;
  final List<Track> items;
  final List<int> itemOffsets;

  const ShuffleSessionPage({
    required this.sessionId,
    required this.offset,
    required this.nextOffset,
    required this.total,
    required this.hasMore,
    required this.items,
    required this.itemOffsets,
  });

  factory ShuffleSessionPage.fromJson(Map<String, dynamic> json) => ShuffleSessionPage(
    sessionId: json['session_id'] as String,
    offset: (json['offset'] as num).toInt(),
    nextOffset: (json['next_offset'] as num).toInt(),
    total: (json['total'] as num).toInt(),
    hasMore: json['has_more'] as bool,
    items: (json['items'] as List).map((value) => Track.fromJson(Map<String, dynamic>.from(value as Map))).toList(),
    itemOffsets: (json['item_offsets'] as List).map((value) => (value as num).toInt()).toList(),
  );
}
