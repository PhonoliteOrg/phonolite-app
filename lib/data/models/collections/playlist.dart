import 'dart:typed_data';

import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

const Object _playlistUnset = Object();

enum PlaylistImageEditKind { keep, clear, replace }

class PlaylistImageEdit {
  final PlaylistImageEditKind kind;
  final Uint8List? bytes;
  final String? contentType;

  const PlaylistImageEdit.keep() : kind = PlaylistImageEditKind.keep, bytes = null, contentType = null;

  const PlaylistImageEdit.clear() : kind = PlaylistImageEditKind.clear, bytes = null, contentType = null;

  const PlaylistImageEdit.replace({required this.bytes, required this.contentType})
    : kind = PlaylistImageEditKind.replace;
}

class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final List<SourceTrackRef> pendingTrackSources;
  final String? description;
  final String? imageRef;
  final String? imagePath;

  /// Server concurrency version; absent for local playlists and older servers.
  final int? revision;

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    this.pendingTrackSources = const [],
    this.description,
    this.imageRef,
    this.imagePath,
    this.revision,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final ids = (json['track_ids'] as List?)?.map((item) => item.toString()).toList() ?? <String>[];

    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackIds: ids,
      pendingTrackSources:
          (json['pending_track_sources'] as List?)
              ?.whereType<Map>()
              .map((source) => SourceTrackRef.fromJson(Map<String, dynamic>.from(source)))
              .where((source) => source.isValid)
              .toList(growable: false) ??
          const [],
      description: JsonValues.nonEmptyString(json['description'] ?? json['summary']),
      imageRef: JsonValues.nonEmptyString(json['image_ref'] ?? json['imageRef']),
      imagePath: JsonValues.nonEmptyString(json['image_path'] ?? json['imagePath']),
      revision: (json['revision'] as num?)?.toInt(),
    );
  }

  int get totalTrackCount => trackIds.length + pendingTrackSources.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'track_ids': trackIds,
    if (pendingTrackSources.isNotEmpty)
      'pending_track_sources': pendingTrackSources.map((source) => source.toJson()).toList(growable: false),
    if (description != null) 'description': description,
    if (imageRef != null) 'image_ref': imageRef,
    if (imagePath != null) 'image_path': imagePath,
    if (revision != null) 'revision': revision,
  };

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    List<SourceTrackRef>? pendingTrackSources,
    Object? description = _playlistUnset,
    Object? imageRef = _playlistUnset,
    Object? imagePath = _playlistUnset,
    Object? revision = _playlistUnset,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      pendingTrackSources: pendingTrackSources ?? this.pendingTrackSources,
      description: identical(description, _playlistUnset) ? this.description : description as String?,
      imageRef: identical(imageRef, _playlistUnset) ? this.imageRef : imageRef as String?,
      imagePath: identical(imagePath, _playlistUnset) ? this.imagePath : imagePath as String?,
      revision: identical(revision, _playlistUnset) ? this.revision : revision as int?,
    );
  }
}
