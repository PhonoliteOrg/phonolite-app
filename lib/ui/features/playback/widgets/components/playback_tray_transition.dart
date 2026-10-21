import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Marks movement rather than button presses, including interactive drags.
/// These async spans identify transitions in DevTools; they are not CPU time.
class PlaybackNowPlayingTrayTransition extends StatefulWidget {
  final Widget child;

  const PlaybackNowPlayingTrayTransition({super.key, required this.child});

  @override
  State<PlaybackNowPlayingTrayTransition> createState() => PlaybackNowPlayingTrayTransitionState();
}

class PlaybackNowPlayingTrayTransitionState extends State<PlaybackNowPlayingTrayTransition> {
  Animation<double>? _animation;
  developer.TimelineTask? _transition;
  double _previousValue = 0;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (kReleaseMode) {
      return;
    }

    final animation = ModalRoute.of(context)?.animation;

    if (identical(animation, _animation)) {
      return;
    }

    _animation?.removeListener(_recordMovement);
    _finishTransition(interrupted: true);

    _animation = animation;
    _previousValue = animation?.value ?? 0;
    animation?.addListener(_recordMovement);
  }

  @override
  void dispose() {
    _animation?.removeListener(_recordMovement);
    _finishTransition(interrupted: true);

    super.dispose();
  }

  void _recordMovement() {
    final value = _animation!.value;

    if (value == _previousValue) {
      return;
    }

    final closing = value < _previousValue;

    if (_transition == null || closing != _closing) {
      _finishTransition(interrupted: true);
      _closing = closing;

      final transition = developer.TimelineTask();
      transition.start('nowPlaying.tray.${closing ? 'close' : 'open'}');
      _transition = transition;
    }

    _previousValue = value;

    if (value == 0 || value == 1) {
      _finishTransition();
    }
  }

  void _finishTransition({bool interrupted = false}) {
    _transition?.finish(arguments: {'interrupted': interrupted});
    _transition = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
