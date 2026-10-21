import 'package:flutter/foundation.dart' show immutable;

@immutable
class CustomShuffleSettings {
  final List<String> artistIds;
  final List<String> genres;
  final List<String> localArtistIds;
  final List<String> localGenres;

  const CustomShuffleSettings({
    this.artistIds = const [],
    this.genres = const [],
    this.localArtistIds = const [],
    this.localGenres = const [],
  });

  static CustomShuffleSettings fromJson(Map<String, dynamic> json) {
    return CustomShuffleSettings(
      artistIds: _normalizeList(json['artistIds']),
      genres: _normalizeList(json['genres'], lowerCase: true),
      localArtistIds: _normalizeList(json['localArtistIds']),
      localGenres: _normalizeList(json['localGenres'], lowerCase: true),
    );
  }

  CustomShuffleSettings copyWith({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) {
    return CustomShuffleSettings(
      artistIds: artistIds ?? this.artistIds,
      genres: genres ?? this.genres,
      localArtistIds: localArtistIds ?? this.localArtistIds,
      localGenres: localGenres ?? this.localGenres,
    );
  }

  Map<String, dynamic> toJson() => {
    'artistIds': artistIds,
    'genres': genres,
    'localArtistIds': localArtistIds,
    'localGenres': localGenres,
  };

  static List<String> _normalizeList(dynamic value, {bool lowerCase = false}) {
    if (value is! List) {
      return const [];
    }

    final seen = <String>{};
    final result = <String>[];

    for (final item in value) {
      var text = item?.toString() ?? '';
      text = text.trim();

      if (text.isEmpty) {
        continue;
      }

      if (lowerCase) {
        text = text.toLowerCase();
      }

      if (seen.add(text)) {
        result.add(text);
      }
    }

    return result;
  }
}
