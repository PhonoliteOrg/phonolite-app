import 'package:phonolite_app/data/structures/serialization/json_values.dart';

/// One identified contributor. Names and joining words are preserved verbatim.
class ArtistCredit {
  final String artistId;
  final String name;
  final String? creditedName;
  final String role;
  final String joinPhrase;

  const ArtistCredit({
    required this.artistId,
    required this.name,
    this.creditedName,
    this.role = 'primary',
    this.joinPhrase = '',
  });

  factory ArtistCredit.fromJson(Map<String, dynamic> json) => ArtistCredit(
    artistId: (json['artist_id'] ?? json['id']) as String? ?? '',
    name: (json['name'] ?? json['artist_name']) as String? ?? '',
    creditedName: json['credited_name'] as String?,
    role: json['role'] as String? ?? 'primary',
    joinPhrase: json['join_phrase'] as String? ?? '',
  );

  String get displayName => JsonValues.nonEmptyString(creditedName) ?? name;

  bool get isAlbumArtist => isAlbumArtistRole(role);

  bool get isPerformingArtist => isPerformingArtistRole(role);

  static bool isAlbumArtistRole(String role) =>
      const {'primary', 'album_artist', 'main', 'joint'}.contains(role.toLowerCase());

  static bool isGuestArtistRole(String role) =>
      const {'track_artist', 'featured_artist', 'featured', 'guest'}.contains(role.toLowerCase());

  static bool isPerformingArtistRole(String role) => isAlbumArtistRole(role) || isGuestArtistRole(role);

  static List<ArtistCredit> listFromJson(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is Map) ArtistCredit.fromJson(Map<String, dynamic>.from(item)),
        ]
      : const [];

  /// Use explicit credits first, then older parallel ID/name lists, then the
  /// primary artist. Albums and tracks share this compatibility policy.
  static List<ArtistCredit> resolve({
    required List<ArtistCredit> credits,
    required List<String> ids,
    required List<String> names,
    required String? primaryId,
    required String primaryName,
  }) {
    if (credits.isNotEmpty) {
      return credits;
    }

    if (ids.isNotEmpty) {
      return [
        for (var i = 0; i < ids.length; i++)
          ArtistCredit(artistId: ids[i], name: i < names.length ? names[i] : primaryName),
      ];
    }

    if (primaryId?.isNotEmpty != true) {
      return const [];
    }

    return [ArtistCredit(artistId: primaryId!, name: primaryName)];
  }

  Map<String, dynamic> toJson() => {
    'artist_id': artistId,
    'name': name,
    'credited_name': creditedName,
    'role': role,
    'join_phrase': joinPhrase,
  };

  @override
  bool operator ==(Object other) =>
      other is ArtistCredit &&
      runtimeType == other.runtimeType &&
      artistId == other.artistId &&
      name == other.name &&
      creditedName == other.creditedName &&
      role == other.role &&
      joinPhrase == other.joinPhrase;

  @override
  int get hashCode => Object.hash(runtimeType, artistId, name, creditedName, role, joinPhrase);
}
