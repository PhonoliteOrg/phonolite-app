import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/audio_stream_quality.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';

void main() {
  test('Auto shows the actual quality independently of measured download speed', () {
    for (final (quality, label) in [
      (AudioStreamQuality.original, 'OG'),
      (AudioStreamQuality.high, 'HQ'),
      (AudioStreamQuality.medium, 'MQ'),
      (AudioStreamQuality.low, 'LQ'),
    ]) {
      final state = _state().copyWith(streamQuality: quality, bitrateKbps: 9999);
      expect(playbackActiveQualityLabel(state), label);
      expect(playbackStreamLabel(state.streamMode), 'AUTO');
    }
  });

  test('manual qualities retain the selector badge without an extra quality tag', () {
    for (final mode in [StreamMode.original, StreamMode.high, StreamMode.medium, StreamMode.low]) {
      final state = _state().copyWith(streamMode: mode, streamQuality: AudioStreamQuality.high);
      expect(playbackActiveQualityLabel(state), isNull);
      expect(playbackRttLabel(state), '42ms');
    }
    expect(playbackStreamLabel(StreamMode.original), 'OG');
  });

  test('unknown, disconnected and idle Auto playback do not guess a quality', () {
    expect(playbackActiveQualityLabel(_state()), isNull);
    final known = _state().copyWith(streamQuality: AudioStreamQuality.medium);
    expect(playbackActiveQualityLabel(known.copyWith(streamConnected: false)), isNull);
    expect(playbackActiveQualityLabel(known.copyWith(track: null)), isNull);
    expect(playbackActiveQualityLabel(known.copyWith(streamQuality: null)), isNull);
    expect(known.copyWith(volume: 0.5).streamQuality, AudioStreamQuality.medium);
  });

  test('local playback hides streaming quality and network measurements', () {
    final state = _state().copyWith(isLocalPlayback: true, streamQuality: AudioStreamQuality.high);
    expect(playbackActiveQualityLabel(state), isNull);
    expect(playbackRttLabel(state), isNull);
    expect(playbackRttLabel(_state().copyWith(streamRttMs: null)), isNull);
  });
}

PlaybackState _state() => PlaybackState(
  track: Track(
    id: 'track',
    title: 'Track',
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    liked: false,
    inPlaylists: false,
  ),
  isPlaying: true,
  isLoading: false,
  position: Duration.zero,
  duration: const Duration(minutes: 3),
  bufferRatio: 0,
  volume: 1,
  shuffleMode: ShuffleMode.off,
  shuffleScope: ActionScope.server,
  repeatMode: PlaybackRepeatMode.off,
  streamMode: StreamMode.auto,
  bitrateKbps: 496.7,
  streamConnected: true,
  streamRttMs: 42,
  queueSource: PlaybackQueueSource.none,
  queueSourcePlaylistId: null,
  localPlaybackSource: LocalPlaybackSource.none,
  isLocalPlayback: false,
);
