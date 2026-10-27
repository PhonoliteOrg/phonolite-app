class ServerCapabilities {
  final bool downloadJobsV2;
  final bool metadataSnapshotsV2;
  final bool eventReplayV2;
  final bool trackFileContractV2;
  final bool artistSummaries;
  final bool artistThumbnails;
  final bool accountCollectionsSync;
  final bool atomicPlaylistTracks;
  final bool accountEventsV2;
  final bool shufflePresets;
  final bool lastTrack;
  final bool playbackResume;
  final bool sessionManagement;
  final bool catalogueEvents;

  ServerCapabilities({
    required this.downloadJobsV2,
    required this.metadataSnapshotsV2,
    required this.eventReplayV2,
    required this.trackFileContractV2,
    this.artistSummaries = false,
    this.artistThumbnails = false,
    this.accountCollectionsSync = false,
    this.atomicPlaylistTracks = false,
    this.accountEventsV2 = false,
    this.shufflePresets = false,
    this.lastTrack = false,
    this.playbackResume = false,
    this.sessionManagement = false,
    this.catalogueEvents = false,
  });

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    return ServerCapabilities(
      downloadJobsV2: _capabilityEnabled(json['download_jobs_v2']),
      metadataSnapshotsV2: _capabilityEnabled(json['metadata_snapshots_v2']),
      eventReplayV2: _capabilityEnabled(json['event_replay_v2']),
      trackFileContractV2: _capabilityEnabled(json['track_file_contract_v2']),
      artistSummaries: _capabilityEnabled(json['artist_summaries']),
      artistThumbnails: _capabilityEnabled(json['artist_thumbnails']),
      accountCollectionsSync: _capabilityEnabled(json['account_collections_sync']),
      atomicPlaylistTracks: _capabilityEnabled(json['atomic_playlist_tracks']),
      accountEventsV2: _capabilityEnabled(json['account_events_v2']),
      shufflePresets: _capabilityEnabled(json['shuffle_presets']),
      lastTrack: _capabilityEnabled(json['last_track']),
      playbackResume: _capabilityEnabled(json['playback_resume']),
      sessionManagement: _capabilityEnabled(json['session_management']),
      catalogueEvents: _capabilityEnabled(json['catalogue_events']),
    );
  }

  static bool _capabilityEnabled(Object? value) {
    final text = value?.toString().trim().toLowerCase();

    return text == '1' || text == 'true' || text == 'yes';
  }
}
