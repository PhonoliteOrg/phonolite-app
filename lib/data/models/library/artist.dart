import 'package:phonolite_app/data/structures/serialization/json_values.dart';

const Object _artistUnset = Object();

class Artist {
  final String id;
  final String name;
  final int albumCount;
  final int collabAlbumCount;
  final int appearanceCount;
  final int otherCreditCount;
  final int? _releaseCount;
  final List<String> genres;
  final String? summary;
  final String? logoRef;
  final String? bannerRef;

  Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    this.collabAlbumCount = 0,
    this.appearanceCount = 0,
    this.otherCreditCount = 0,
    int? releaseCount,
    this.genres = const [],
    this.summary,
    this.logoRef,
    this.bannerRef,
  }) : _releaseCount = releaseCount;

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String,
      name: json['name'] as String,
      albumCount: JsonValues.firstInteger(json, const ['album_count', 'albumCount']),
      collabAlbumCount: JsonValues.firstInteger(json, const ['collab_album_count']),
      appearanceCount: JsonValues.firstInteger(json, const ['appearance_count']),
      otherCreditCount: JsonValues.firstInteger(json, const ['other_credit_count']),
      releaseCount: JsonValues.optionalInteger(json['release_count']),
      genres: (json['genres'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      summary: json['summary'] as String?,
      logoRef: json['logo_ref'] as String?,
      bannerRef: json['banner_ref'] as String?,
    );
  }

  /// Unique albums across headline releases and billed song appearances.
  int get releaseCount {
    if (_releaseCount != null) {
      return _releaseCount;
    }

    // Older servers include appearances and other credits in collaborations.
    // Taking the largest count also handles older responses that omit collabs,
    // without counting overlapping credit categories twice.
    final contributions = [collabAlbumCount, appearanceCount].reduce((a, b) => a > b ? a : b);

    return albumCount + contributions;
  }

  /// Compares persisted metadata without constructing JSON maps or strings.
  bool hasSameMetadata(Artist other) {
    if (identical(this, other)) {
      return true;
    }

    if (id != other.id ||
        name != other.name ||
        albumCount != other.albumCount ||
        collabAlbumCount != other.collabAlbumCount ||
        appearanceCount != other.appearanceCount ||
        otherCreditCount != other.otherCreditCount ||
        _releaseCount != other._releaseCount ||
        summary != other.summary ||
        logoRef != other.logoRef ||
        bannerRef != other.bannerRef ||
        genres.length != other.genres.length) {
      return false;
    }

    if (!identical(genres, other.genres)) {
      for (var i = 0; i < genres.length; i++) {
        if (genres[i] != other.genres[i]) {
          return false;
        }
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'album_count': albumCount,
    'collab_album_count': collabAlbumCount,
    'appearance_count': appearanceCount,
    'other_credit_count': otherCreditCount,
    if (_releaseCount != null) 'release_count': _releaseCount,
    'genres': genres,
    'summary': summary,
    'logo_ref': logoRef,
    'banner_ref': bannerRef,
  };

  Artist copyWith({
    String? id,
    String? name,
    int? albumCount,
    int? collabAlbumCount,
    int? appearanceCount,
    int? otherCreditCount,
    Object? releaseCount = _artistUnset,
    List<String>? genres,
    Object? summary = _artistUnset,
    Object? logoRef = _artistUnset,
    Object? bannerRef = _artistUnset,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      albumCount: albumCount ?? this.albumCount,
      collabAlbumCount: collabAlbumCount ?? this.collabAlbumCount,
      appearanceCount: appearanceCount ?? this.appearanceCount,
      otherCreditCount: otherCreditCount ?? this.otherCreditCount,
      releaseCount: identical(releaseCount, _artistUnset) ? _releaseCount : releaseCount as int?,
      genres: genres ?? this.genres,
      summary: identical(summary, _artistUnset) ? this.summary : summary as String?,
      logoRef: identical(logoRef, _artistUnset) ? this.logoRef : logoRef as String?,
      bannerRef: identical(bannerRef, _artistUnset) ? this.bannerRef : bannerRef as String?,
    );
  }
}
