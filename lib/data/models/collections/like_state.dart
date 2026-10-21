class ServerLikeState {
  final String trackId;
  final bool liked;
  final int updatedAt;

  ServerLikeState({required this.trackId, required this.liked, required this.updatedAt});

  factory ServerLikeState.fromJson(Map<String, dynamic> json) {
    return ServerLikeState(
      trackId: json['track_id']?.toString() ?? '',
      liked: json['liked'] as bool? ?? false,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
