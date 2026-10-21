class TrackMatchDescriptor {
  final String localTrackId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int? trackNo;
  final int? discNo;
  final String? serverTrackId;

  TrackMatchDescriptor({
    required this.localTrackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    this.trackNo,
    this.discNo,
    this.serverTrackId,
  });

  Map<String, dynamic> toJson() => {
    'local_track_id': localTrackId,
    'title': title,
    'artist': artist,
    'album': album,
    'duration_ms': durationMs,
    'track_no': trackNo,
    'disc_no': discNo,
    if (serverTrackId != null && serverTrackId!.trim().isNotEmpty) 'server_track_id': serverTrackId,
  };
}

class TrackMatchResult {
  final String localTrackId;
  final String serverTrackId;
  final double confidence;
  final String matchKind;
  final bool serverLiked;
  final int serverUpdatedAt;

  TrackMatchResult({
    required this.localTrackId,
    required this.serverTrackId,
    required this.confidence,
    required this.matchKind,
    required this.serverLiked,
    required this.serverUpdatedAt,
  });

  factory TrackMatchResult.fromJson(Map<String, dynamic> json) {
    return TrackMatchResult(
      localTrackId: json['local_track_id']?.toString() ?? '',
      serverTrackId: json['server_track_id']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      matchKind: json['match_kind']?.toString() ?? 'metadata_strict',
      serverLiked: json['server_liked'] as bool? ?? false,
      serverUpdatedAt: (json['server_updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
