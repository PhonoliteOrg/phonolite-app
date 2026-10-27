import 'package:flutter/foundation.dart' show immutable;

/// Account-owned rules. Applying them to playback is a separate device action.
@immutable
class ShufflePreset {
  final String id;
  final String name;
  final List<String> artistIds;
  final List<String> genres;
  final int revision;

  ShufflePreset({
    required this.id,
    required this.name,
    required List<String> artistIds,
    required List<String> genres,
    required this.revision,
  }) : artistIds = List.unmodifiable(artistIds),
       genres = List.unmodifiable(genres);

  static ShufflePreset fromJson(Map<String, dynamic> json) => ShufflePreset(
    id: json['id'] as String,
    name: json['name'] as String,
    artistIds: (json['artist_ids'] as List).cast<String>(),
    genres: (json['genres'] as List).cast<String>(),
    revision: (json['revision'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'artist_ids': artistIds,
    'genres': genres,
    'revision': revision,
  };
}
