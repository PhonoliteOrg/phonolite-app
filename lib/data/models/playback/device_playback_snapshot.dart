import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/rules/playback/playback_resume_values.dart';

/// Device-only order and seek state. Local IDs are never sent to the account API.
class DevicePlaybackSnapshot {
  static const schemaVersion = 1;

  final PlaybackResumeCheckpoint? checkpoint;
  final List<String> queueTrackIds;
  final ShuffleMode localShuffleMode;
  final ShuffleMode serverShuffleMode;
  final ActionScope shuffleScope;
  final int positionMs;

  DevicePlaybackSnapshot({
    this.checkpoint,
    List<String> queueTrackIds = const [],
    this.localShuffleMode = ShuffleMode.off,
    this.serverShuffleMode = ShuffleMode.off,
    this.shuffleScope = ActionScope.local,
    this.positionMs = 0,
  }) : queueTrackIds = List.unmodifiable(queueTrackIds) {
    PlaybackResumeValues.identifiers(queueTrackIds, maximum: PlaybackResumeValues.maxQueueTracks);
    PlaybackResumeValues.integer(positionMs);
  }

  factory DevicePlaybackSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported playback snapshot version');
    }

    final scope = switch (json['shuffle_scope']) {
      'local' => ActionScope.local,
      'server' => ActionScope.server,
      _ => throw const FormatException('Invalid playback scope'),
    };

    return DevicePlaybackSnapshot(
      checkpoint: json['checkpoint'] == null
          ? null
          : PlaybackResumeCheckpoint.fromJson(PlaybackResumeValues.map(json['checkpoint'])),
      queueTrackIds: PlaybackResumeValues.identifiers(
        json['queue_track_ids'],
        maximum: PlaybackResumeValues.maxQueueTracks,
      ),
      localShuffleMode: PlaybackResumeValues.shuffle(json['local_shuffle_mode']),
      serverShuffleMode: PlaybackResumeValues.shuffle(json['server_shuffle_mode']),
      shuffleScope: scope,
      positionMs: PlaybackResumeValues.integer(json['position_ms']),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'checkpoint': checkpoint?.toJson(),
    'queue_track_ids': queueTrackIds,
    'local_shuffle_mode': PlaybackResumeValues.shuffleName(localShuffleMode),
    'server_shuffle_mode': PlaybackResumeValues.shuffleName(serverShuffleMode),
    'shuffle_scope': shuffleScope.name,
    'position_ms': positionMs,
  };
}
