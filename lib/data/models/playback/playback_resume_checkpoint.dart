import 'package:phonolite_app/data/models/playback/playback_source_context.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/rules/playback/playback_resume_values.dart';

const Object _resumeUnset = Object();

/// One coherent logical playback selection; it contains no credentials or paths.
class PlaybackResumeCheckpoint {
  final String trackId;
  final PlaybackSourceContext source;
  final ShuffleMode shuffleMode;
  final PlaybackSourceContext shuffleContext;
  final String? deckId;
  final int cursor;

  PlaybackResumeCheckpoint({
    required this.trackId,
    required this.source,
    required this.shuffleMode,
    required this.shuffleContext,
    this.deckId,
    this.cursor = 0,
  }) {
    PlaybackResumeValues.identifier(trackId);
    PlaybackResumeValues.integer(cursor);

    if (deckId != null) {
      PlaybackResumeValues.identifier(deckId);
    }
  }

  factory PlaybackResumeCheckpoint.fromJson(Map<String, dynamic> json) => PlaybackResumeCheckpoint(
    trackId: PlaybackResumeValues.identifier(json['track_id']),
    source: PlaybackSourceContext.fromJson(PlaybackResumeValues.map(json['source'])),
    shuffleMode: PlaybackResumeValues.shuffle(json['shuffle_mode']),
    shuffleContext: PlaybackSourceContext.fromJson(PlaybackResumeValues.map(json['shuffle_context'])),
    deckId: json['deck_id'] == null ? null : PlaybackResumeValues.identifier(json['deck_id']),
    cursor: PlaybackResumeValues.integer(json['cursor']),
  );

  PlaybackResumeCheckpoint copyWith({
    String? trackId,
    PlaybackSourceContext? source,
    ShuffleMode? shuffleMode,
    PlaybackSourceContext? shuffleContext,
    Object? deckId = _resumeUnset,
    int? cursor,
  }) => PlaybackResumeCheckpoint(
    trackId: trackId ?? this.trackId,
    source: source ?? this.source,
    shuffleMode: shuffleMode ?? this.shuffleMode,
    shuffleContext: shuffleContext ?? this.shuffleContext,
    deckId: identical(deckId, _resumeUnset) ? this.deckId : deckId as String?,
    cursor: cursor ?? this.cursor,
  );

  Map<String, dynamic> toJson() => {
    'track_id': trackId,
    'source': source.toJson(),
    'shuffle_mode': PlaybackResumeValues.shuffleName(shuffleMode),
    'shuffle_context': shuffleContext.toJson(),
    if (deckId != null) 'deck_id': deckId,
    'cursor': cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is PlaybackResumeCheckpoint &&
      trackId == other.trackId &&
      source == other.source &&
      shuffleMode == other.shuffleMode &&
      shuffleContext == other.shuffleContext &&
      deckId == other.deckId &&
      cursor == other.cursor;

  @override
  int get hashCode => Object.hash(trackId, source, shuffleMode, shuffleContext, deckId, cursor);
}
