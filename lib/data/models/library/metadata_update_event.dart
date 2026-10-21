import 'package:phonolite_app/data/structures/serialization/json_values.dart';

class MetadataUpdateEvent {
  final int revision;
  final String kind;
  final String id;
  final String? albumId;
  final String? artistId;
  final int updatedAt;

  MetadataUpdateEvent({
    required this.revision,
    required this.kind,
    required this.id,
    required this.updatedAt,
    this.albumId,
    this.artistId,
  });

  factory MetadataUpdateEvent.fromJson(Map<String, dynamic> json) {
    return MetadataUpdateEvent(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      albumId: JsonValues.nonEmptyString(json['album_id']),
      artistId: JsonValues.nonEmptyString(json['artist_id']),
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
