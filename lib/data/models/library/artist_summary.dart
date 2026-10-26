import 'package:phonolite_app/data/models/library/artist.dart';

/// Library and selection metadata; biographies and release graphs stay in detail reads.
class ArtistSummary {
  final String id;
  final String name;
  final List<String> genres;
  final String? logoRef;
  final int albumCount;
  final int collabAlbumCount;
  final int appearanceCount;
  final int otherCreditCount;
  final int? releaseCount;
  final String? metadataRevision;

  ArtistSummary({
    required this.id,
    required this.name,
    List<String> genres = const [],
    this.logoRef,
    this.albumCount = 0,
    this.collabAlbumCount = 0,
    this.appearanceCount = 0,
    this.otherCreditCount = 0,
    this.releaseCount,
    this.metadataRevision,
  }) : genres = List.unmodifiable(genres);

  factory ArtistSummary.fromJson(Map<String, dynamic> json) => ArtistSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    genres: (json['genres'] as List?)?.map((value) => value.toString()).toList() ?? const [],
    logoRef: json['logo_ref'] as String?,
    albumCount: (json['album_count'] as num?)?.toInt() ?? 0,
    collabAlbumCount: (json['collab_album_count'] as num?)?.toInt() ?? 0,
    appearanceCount: (json['appearance_count'] as num?)?.toInt() ?? 0,
    otherCreditCount: (json['other_credit_count'] as num?)?.toInt() ?? 0,
    releaseCount: (json['release_count'] as num?)?.toInt(),
    metadataRevision: json['metadata_revision']?.toString(),
  );

  factory ArtistSummary.fromArtist(Artist artist) => ArtistSummary(
    id: artist.id,
    name: artist.name,
    genres: artist.genres,
    logoRef: artist.logoRef,
    albumCount: artist.albumCount,
    collabAlbumCount: artist.collabAlbumCount,
    appearanceCount: artist.appearanceCount,
    otherCreditCount: artist.otherCreditCount,
    releaseCount: artist.releaseCount,
  );

  /// Conservative retained-memory charge, including collection/object overhead.
  int get retainedBytes =>
      256 +
      2 * (id.length + name.length + (logoRef?.length ?? 0) + (metadataRevision?.length ?? 0)) +
      genres.fold(0, (bytes, genre) => bytes + 48 + 2 * genre.length);

  Artist toArtist() => Artist(
    id: id,
    name: name,
    albumCount: albumCount,
    collabAlbumCount: collabAlbumCount,
    appearanceCount: appearanceCount,
    otherCreditCount: otherCreditCount,
    releaseCount: releaseCount,
    genres: genres,
    logoRef: logoRef,
  );
}

class ArtistSummaryPage {
  final List<ArtistSummary> items;
  final int total;
  final int? nextOffset;
  final String browseRevision;

  ArtistSummaryPage({
    required List<ArtistSummary> items,
    required this.total,
    this.nextOffset,
    required this.browseRevision,
  }) : items = List.unmodifiable(items);

  factory ArtistSummaryPage.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List).map(
      (value) => ArtistSummary.fromJson(Map<String, dynamic>.from(value as Map)),
    );
    final total = (json['total'] as num).toInt();
    final nextOffset = (json['next_offset'] as num?)?.toInt();
    final revision = json['browse_revision'];

    if (total < 0 ||
        (nextOffset != null && (nextOffset < 0 || nextOffset > total)) ||
        revision is! String ||
        revision.isEmpty) {
      throw const FormatException('Invalid artist summary page bounds');
    }

    return ArtistSummaryPage(items: items.toList(), total: total, nextOffset: nextOffset, browseRevision: revision);
  }

  int get retainedBytes => 128 + browseRevision.length * 2 + items.fold(0, (bytes, item) => bytes + item.retainedBytes);
}
