import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/rules/playback/playback_resume_values.dart';

class AccountPlaybackSnapshot {
  final int revision;
  final String? generation;
  final PlaybackResumeCheckpoint? checkpoint;
  final String? reason;

  const AccountPlaybackSnapshot({required this.revision, this.generation, this.checkpoint, this.reason});

  factory AccountPlaybackSnapshot.fromJson(Map<String, dynamic> json) {
    final reason = json['reason'];

    if (reason != null && (reason is! String || reason.length > 256)) {
      throw const FormatException('Invalid playback reconciliation reason');
    }

    return AccountPlaybackSnapshot(
      revision: PlaybackResumeValues.integer(json['revision']),
      generation: json['generation'] == null ? null : PlaybackResumeValues.identifier(json['generation']),
      checkpoint: json['checkpoint'] == null
          ? null
          : PlaybackResumeCheckpoint.fromJson(PlaybackResumeValues.map(json['checkpoint'])),
      reason: reason as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'generation': generation,
    'checkpoint': checkpoint?.toJson(),
    if (reason != null) 'reason': reason,
  };
}
