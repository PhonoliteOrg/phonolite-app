class ServerCapabilities {
  final bool downloadJobsV2;
  final bool metadataSnapshotsV2;
  final bool eventReplayV2;
  final bool trackFileContractV2;
  final bool artistSummaries;
  final bool artistThumbnails;

  ServerCapabilities({
    required this.downloadJobsV2,
    required this.metadataSnapshotsV2,
    required this.eventReplayV2,
    required this.trackFileContractV2,
    this.artistSummaries = false,
    this.artistThumbnails = false,
  });

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    return ServerCapabilities(
      downloadJobsV2: _capabilityEnabled(json['download_jobs_v2']),
      metadataSnapshotsV2: _capabilityEnabled(json['metadata_snapshots_v2']),
      eventReplayV2: _capabilityEnabled(json['event_replay_v2']),
      trackFileContractV2: _capabilityEnabled(json['track_file_contract_v2']),
      artistSummaries: _capabilityEnabled(json['artist_summaries']),
      artistThumbnails: _capabilityEnabled(json['artist_thumbnails']),
    );
  }

  static bool _capabilityEnabled(Object? value) {
    final text = value?.toString().trim().toLowerCase();

    return text == '1' || text == 'true' || text == 'yes';
  }
}
