import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/structures/serialization/json_values.dart';

const Object _albumUnset = Object();

class Album {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final List<String> artistIds;
  final List<String> artistNames;
  final List<ArtistCredit> artistCredits;
  final int trackCount;
  final int? year;
  final List<String> genres;
  final String? summary;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.trackCount,
    this.artistIds = const [],
    this.artistNames = const [],
    this.artistCredits = const [],
    this.year,
    this.genres = const [],
    this.summary,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: _albumArtistName(json),
      artistId: json['artist_id'] as String? ?? '',
      artistIds: JsonValues.strings(json['artist_ids']),
      artistNames: JsonValues.strings(json['artist_names']),
      artistCredits: ArtistCredit.listFromJson(json['artist_credits']),
      trackCount: JsonValues.firstInteger(json, const [
        'track_count',
        'trackCount',
        'tracks_count',
        'track_total',
        'total_tracks',
      ]),
      year: JsonValues.optionalInteger(json['year']),
      genres: (json['genres'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      summary: json['summary'] as String?,
    );
  }

  List<ArtistCredit> get credits => ArtistCredit.resolve(
    credits: artistCredits,
    ids: artistIds,
    names: artistNames,
    primaryId: artistId,
    primaryName: artist,
  );

  bool get isCollaboration =>
      credits
          .where((credit) => credit.isAlbumArtist)
          .map((credit) => credit.artistId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .length >
      1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artist_id': artistId,
    'artist_ids': artistIds,
    'artist_names': artistNames,
    'artist_credits': artistCredits.map((credit) => credit.toJson()).toList(),
    'track_count': trackCount,
    'year': year,
    'genres': genres,
    'summary': summary,
  };

  Album copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    List<String>? artistIds,
    List<String>? artistNames,
    List<ArtistCredit>? artistCredits,
    int? trackCount,
    Object? year = _albumUnset,
    List<String>? genres,
    Object? summary = _albumUnset,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      artistIds: artistIds ?? this.artistIds,
      artistNames: artistNames ?? this.artistNames,
      artistCredits: artistCredits ?? this.artistCredits,
      trackCount: trackCount ?? this.trackCount,
      year: identical(year, _albumUnset) ? this.year : year as int?,
      genres: genres ?? this.genres,
      summary: identical(summary, _albumUnset) ? this.summary : summary as String?,
    );
  }
}

String _albumArtistName(Map<String, dynamic> json) {
  final direct = JsonValues.nonEmptyString(json['artist']);
  if (direct != null) {
    return direct;
  }

  final browseName = JsonValues.nonEmptyString(json['artist_name']);
  if (browseName != null) {
    return browseName;
  }

  final names =
      (json['artist_names'] as List?)
          ?.map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList() ??
      const <String>[];

  return names.join(', ');
}
