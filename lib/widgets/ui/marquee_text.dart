import 'dart:async';

import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 32,
    this.gap = 24,
    this.pause = const Duration(milliseconds: 800),
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final double gap;
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  Timer? _pauseTimer;
  int _loopGeneration = 0;
  bool _shouldScroll = false;
  double? _viewportWidth;
  double? _textWidth;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.gap != widget.gap ||
        oldWidget.pause != widget.pause) {
      _restartLoop();
    }
  }

  @override
  void dispose() {
    _cancelLoop();
    _controller.dispose();
    super.dispose();
  }

  void _cancelLoop() {
    _loopGeneration++;
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  bool _isCurrentLoop(int generation) =>
      mounted && _shouldScroll && generation == _loopGeneration;

  void _restartLoop() {
    _cancelLoop();
    if (_controller.hasClients) {
      _controller.jumpTo(0);
    }
    if (_shouldScroll) {
      _scheduleScroll(
        _loopGeneration,
        const Duration(milliseconds: 200) + widget.pause,
      );
    }
  }

  void _scheduleScroll(int generation, Duration delay) {
    if (!_isCurrentLoop(generation)) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(delay, () {
      _pauseTimer = null;
      unawaited(_scrollToEnd(generation));
    });
  }

  Future<void> _scrollToEnd(int generation) async {
    if (!_isCurrentLoop(generation)) return;
    if (!_controller.hasClients) {
      _scheduleScroll(generation, const Duration(milliseconds: 200));
      return;
    }
    final position = _controller.position;
    final max = position.maxScrollExtent;
    if (max <= 0) {
      _scheduleScroll(generation, const Duration(milliseconds: 400));
      return;
    }
    final distance = max - position.pixels;
    final durationMs = (distance / widget.velocity * 1000).round();
    await _controller.animateTo(
      max,
      duration: Duration(milliseconds: durationMs > 0 ? durationMs : 1),
      curve: Curves.linear,
    );
    if (!_isCurrentLoop(generation)) return;
    _pauseTimer = Timer(widget.pause, () {
      _pauseTimer = null;
      if (!_isCurrentLoop(generation)) return;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      _scheduleScroll(generation, widget.pause);
    });
  }

  void _setShouldScroll(bool value, double viewportWidth, double textWidth) {
    if (_shouldScroll == value &&
        _viewportWidth == viewportWidth &&
        _textWidth == textWidth) {
      return;
    }
    _shouldScroll = value;
    _viewportWidth = viewportWidth;
    _textWidth = textWidth;
    _restartLoop();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var effectiveStyle = DefaultTextStyle.of(
          context,
        ).style.merge(widget.style);
        if (MediaQuery.boldTextOf(context)) {
          effectiveStyle = effectiveStyle.merge(
            const TextStyle(fontWeight: FontWeight.bold),
          );
        }
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout();
        final textWidth = painter.width;
        painter.dispose();
        final shouldScroll =
            constraints.hasBoundedWidth && textWidth > constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _setShouldScroll(shouldScroll, constraints.maxWidth, textWidth);
          }
        });

        if (!shouldScroll) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: widget.style, maxLines: 1),
                  SizedBox(width: widget.gap),
                  Text(widget.text, style: widget.style, maxLines: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
