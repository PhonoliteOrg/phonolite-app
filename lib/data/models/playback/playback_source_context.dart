import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/rules/playback/playback_resume_values.dart';

/// Logical collection identity. Transport (stream or downloaded file) is separate.
class PlaybackSourceContext {
  final String kind;
  final String? id;
  final List<String> artistIds;
  final List<String> genres;

  PlaybackSourceContext({
    required this.kind,
    this.id,
    List<String> artistIds = const [],
    List<String> genres = const [],
  }) : artistIds = List.unmodifiable(artistIds),
       genres = List.unmodifiable(genres) {
    _validate();
  }

  factory PlaybackSourceContext.fromJson(Map<String, dynamic> json) => PlaybackSourceContext(
    kind: json['kind'] is String ? json['kind'] as String : '',
    id: json['id'] == null ? null : PlaybackResumeValues.identifier(json['id']),
    artistIds: PlaybackResumeValues.identifiers(json['artist_ids']),
    genres: PlaybackResumeValues.identifiers(json['genres']),
  );

  bool get isCollection => kind != 'standalone';

  Map<String, dynamic> toJson() => {'kind': kind, if (id != null) 'id': id, 'artist_ids': artistIds, 'genres': genres};

  void _validate() {
    if (!PlaybackResumeValues.sourceKinds.contains(kind)) {
      throw const FormatException('Invalid playback source');
    }

    final needsId = {'playlist', 'album', 'artist'}.contains(kind);

    if (needsId != (id != null)) {
      throw const FormatException('Invalid playback source identifier');
    }

    if (id != null) {
      PlaybackResumeValues.identifier(id);
    }

    PlaybackResumeValues.identifiers(artistIds);
    PlaybackResumeValues.identifiers(genres);

    if (kind != 'custom' && (artistIds.isNotEmpty || genres.isNotEmpty)) {
      throw const FormatException('Filters require a custom playback source');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackSourceContext &&
      kind == other.kind &&
      id == other.id &&
      listEquals(artistIds, other.artistIds) &&
      listEquals(genres, other.genres);

  @override
  int get hashCode => Object.hash(kind, id, Object.hashAll(artistIds), Object.hashAll(genres));
}
