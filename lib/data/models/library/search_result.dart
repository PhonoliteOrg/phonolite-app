class SearchResult {
  final String kind;
  final String id;
  final String title;
  final String? subtitle;
  final int? score;
  final String? albumId;
  final String? artworkPath;

  SearchResult({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
    this.albumId,
    this.artworkPath,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      kind: json['kind'] as String? ?? 'track',
      id: json['id'] as String,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? json['artist'] as String?,
      score: (json['score'] as num?)?.toInt(),
      albumId: json['album_id'] as String?,
    );
  }
}
