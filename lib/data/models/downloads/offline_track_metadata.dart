import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/track.dart';

class OfflineTrackMetadata {
  static const int currentSchemaVersion = 6;

  final int schemaVersion;
  final Track track;
  final Album album;
  final Artist artist;
  final List<Artist> artists;

  OfflineTrackMetadata({
    required this.schemaVersion,
    required this.track,
    required this.album,
    required this.artist,
    this.artists = const [],
  });

  factory OfflineTrackMetadata.fromJson(Map<String, dynamic> json) {
    return OfflineTrackMetadata(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map? ?? const {})),
      album: Album.fromJson(Map<String, dynamic>.from(json['album'] as Map? ?? const {})),
      artist: Artist.fromJson(Map<String, dynamic>.from(json['artist'] as Map? ?? const {})),
      artists: _artistsFromJson(json['artists']),
    );
  }

  List<Artist> get allArtists => <String, Artist>{
    artist.id: artist,
    for (final artist in track.offlineArtists) artist.id: artist,
    for (final artist in artists) artist.id: artist,
  }.values.toList();

  OfflineTrackMetadata copyWith({Track? track, Album? album, Artist? artist, List<Artist>? artists}) {
    return OfflineTrackMetadata(
      schemaVersion: schemaVersion,
      track: track ?? this.track,
      album: album ?? this.album,
      artist: artist ?? this.artist,
      artists: artists ?? this.artists,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'track': track.toJson(),
    'album': album.toJson(),
    'artist': artist.toJson(),
    'artists': allArtists.map((artist) => artist.toJson()).toList(),
  };
}

List<Artist> _artistsFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Artist.fromJson(Map<String, dynamic>.from(item)),
      ]
    : const [];
