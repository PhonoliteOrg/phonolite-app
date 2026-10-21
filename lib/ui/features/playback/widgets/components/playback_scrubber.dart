import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/scrubber_display_position.dart';

/// Shared input contract for compact and expanded progress presentations.
abstract class PlaybackScrubber extends StatefulWidget {
  final SliderThemeData sliderTheme;
  final double maxSeconds;
  final Duration position;
  final Duration duration;
  final bool animate;
  final double bufferedPositionSeconds;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekPreview;
  final bool enabled;

  const PlaybackScrubber({
    super.key,
    required this.sliderTheme,
    required this.maxSeconds,
    required this.position,
    required this.duration,
    required this.animate,
    required this.bufferedPositionSeconds,
    required this.onSeek,
    required this.onSeekPreview,
    required this.enabled,
  });
}

/// Owns visual interpolation, drag preview and timer cleanup for every scrubber.
/// Actual playback commands remain supplied callbacks from the controller.
abstract class PlaybackScrubberState<T extends PlaybackScrubber> extends State<T> {
  Timer? _timer;
  Duration _displayPosition = Duration.zero;
  Duration? _dragPosition;
  DateTime? _lastTickAt;
  bool _isDragging = false;

  @protected
  bool get respectsTickerMode => false;

  @protected
  String? get tickTimelineLabel => null;

  @protected
  Duration get displayPosition => _displayPosition;

  @protected
  double get positionSeconds {
    final position = _isDragging && _dragPosition != null ? _dragPosition! : _displayPosition;

    return (position.inMilliseconds / 1000.0).clamp(0.0, widget.maxSeconds);
  }

  @protected
  double get bufferedPositionSeconds =>
      math.max(widget.bufferedPositionSeconds, positionSeconds).clamp(0.0, widget.maxSeconds);

  @override
  void initState() {
    super.initState();

    _displayPosition = widget.position;
    _lastTickAt = DateTime.now();

    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isDragging) {
      _lastTickAt = DateTime.now();

      return;
    }

    final authoritativeDeltaMs = widget.position.inMilliseconds - oldWidget.position.inMilliseconds;

    if (!widget.animate ||
        !oldWidget.animate ||
        widget.duration != oldWidget.duration ||
        authoritativeDeltaMs.abs() >= playbackScrubberAuthoritativeDiscontinuityMs) {
      _displayPosition = widget.position;
      _lastTickAt = DateTime.now();

      return;
    }

    _displayPosition = playbackBoundedScrubberDisplayPosition(
      displayPosition: _displayPosition,
      authoritativePosition: widget.position,
      duration: widget.duration,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();

    super.dispose();
  }

  @protected
  void beginDrag(double value) {
    final position = _sliderPosition(value);

    setState(() {
      _isDragging = true;
      _dragPosition = position;
      _displayPosition = position;
    });
  }

  @protected
  void updateDrag(double value) {
    final position = _sliderPosition(value);

    setState(() {
      _dragPosition = position;
      _displayPosition = position;
    });

    widget.onSeekPreview(position);
  }

  @protected
  void endDrag(double value) {
    final position = _sliderPosition(value);

    setState(() {
      _isDragging = false;
      _dragPosition = null;
      _displayPosition = position;
      _lastTickAt = DateTime.now();
    });

    widget.onSeek(position);
  }

  void _tick() {
    final label = tickTimelineLabel;

    if (label != null) {
      developer.Timeline.startSync(label);
    }

    final now = DateTime.now();

    try {
      final lastTickAt = _lastTickAt;

      _lastTickAt = now;

      if (!mounted || lastTickAt == null || (respectsTickerMode && !TickerMode.of(context))) {
        return;
      }

      if (_isDragging) {
        return;
      }

      if (!widget.animate) {
        if (_displayPosition != widget.position) {
          setState(() => _displayPosition = widget.position);
        }

        return;
      }

      var elapsedMs = now.difference(lastTickAt).inMilliseconds;

      if (elapsedMs <= 0) {
        return;
      }

      if (elapsedMs > 500) {
        elapsedMs = 250;
      }

      final nextPosition = playbackBoundedScrubberDisplayPosition(
        displayPosition: Duration(milliseconds: _displayPosition.inMilliseconds + elapsedMs),
        authoritativePosition: widget.position,
        duration: widget.duration,
      );

      if (nextPosition != _displayPosition) {
        setState(() => _displayPosition = nextPosition);
      }
    } finally {
      if (label != null) {
        developer.Timeline.finishSync();
      }
    }
  }

  Duration _sliderPosition(double value) => Duration(milliseconds: (value * 1000).round());
}
