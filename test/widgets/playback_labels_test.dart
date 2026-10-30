import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';

void main() {
  test('Original streaming displays its badge and available network measurements', () {
    final state = _state();

    expect(playbackStreamLabel(StreamMode.original), 'OG');
    expect(playbackBitrateLabel(state), '497 KBPS');
    expect(playbackRttLabel(state), '42ms');
  });

  test('local playback hides network measurements regardless of saved quality', () {
    final state = _state().copyWith(isLocalPlayback: true);

    expect(playbackBitrateLabel(state), isNull);
    expect(playbackRttLabel(state), isNull);
  });

  test('Original streaming hides unavailable network measurements', () {
    final state = _state().copyWith(bitrateKbps: null, streamRttMs: null);

    expect(playbackBitrateLabel(state), isNull);
    expect(playbackRttLabel(state), isNull);
  });
}

PlaybackState _state() => PlaybackState(
  track: null,
  isPlaying: true,
  isLoading: false,
  position: Duration.zero,
  duration: const Duration(minutes: 3),
  bufferRatio: 0,
  volume: 1,
  shuffleMode: ShuffleMode.off,
  shuffleScope: ActionScope.server,
  repeatMode: PlaybackRepeatMode.off,
  streamMode: StreamMode.original,
  bitrateKbps: 496.7,
  streamConnected: true,
  streamRttMs: 42,
  queueSource: PlaybackQueueSource.none,
  queueSourcePlaylistId: null,
  localPlaybackSource: LocalPlaybackSource.none,
  isLocalPlayback: false,
);
