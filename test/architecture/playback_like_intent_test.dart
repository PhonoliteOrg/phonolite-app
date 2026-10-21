import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';

class _LikeActions extends Fake implements AppController {
  final serverTracks = <Track>[];
  final localTracks = <Track>[];
  final completion = Completer<void>();

  @override
  Future<void> toggleLike(Track track) {
    serverTracks.add(track);
    return completion.future;
  }

  @override
  Future<void> toggleLocalLike(Track track) {
    localTracks.add(track);
    return completion.future;
  }
}

class _Playback extends Fake implements PlaybackState {
  @override
  final Track? track;
  @override
  final bool isLocalPlayback;
  @override
  final PlaybackQueueSource queueSource;

  _Playback({
    required this.track,
    this.isLocalPlayback = false,
    this.queueSource = PlaybackQueueSource.none,
  });
}

void main() {
  final track = Track(
    id: 'track-1',
    title: 'Track',
    artist: 'Artist',
    album: 'Album',
    durationMs: 1000,
    liked: false,
    inPlaylists: false,
  );

  test('like intent uses captured source and preserves action completion', () {
    for (final source in [
      (local: false, queue: PlaybackQueueSource.none, routesLocal: false),
      (local: true, queue: PlaybackQueueSource.none, routesLocal: true),
      (local: false, queue: PlaybackQueueSource.offline, routesLocal: true),
    ]) {
      final actions = _LikeActions();
      final playback = _Playback(
        track: track,
        isLocalPlayback: source.local,
        queueSource: source.queue,
      );
      final completion = PlaybackControlsController.toggleLike(
        actions,
        playback,
      );

      expect(identical(completion, actions.completion.future), isTrue);
      expect(actions.localTracks, source.routesLocal ? [track] : isEmpty);
      expect(actions.serverTracks, source.routesLocal ? isEmpty : [track]);
      actions.completion.complete();
    }
  });

  test('like intent has no action when its snapshot has no track', () async {
    final actions = _LikeActions();
    await PlaybackControlsController.toggleLike(
      actions,
      _Playback(track: null),
    );

    expect(actions.localTracks, isEmpty);
    expect(actions.serverTracks, isEmpty);
  });
}
