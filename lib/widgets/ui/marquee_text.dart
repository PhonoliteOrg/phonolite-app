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
  bool _running = false;
  bool _shouldScroll = false;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.gap != widget.gap ||
        oldWidget.pause != widget.pause) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
    }
  }

  @override
  void dispose() {
    _running = false;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startLoop() async {
    if (_running || !_shouldScroll) {
      return;
    }
    _running = true;
    await Future.delayed(const Duration(milliseconds: 200));
    while (mounted && _running) {
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final position = _controller.position;
      final max = position.maxScrollExtent;
      if (max <= 0) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }
      await Future.delayed(widget.pause);
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final distance = max - _controller.position.pixels;
      final durationMs = (distance / widget.velocity * 1000).round();
      await _controller.animateTo(
        max,
        duration: Duration(milliseconds: durationMs.clamp(1, 60000)),
        curve: Curves.linear,
      );
      await Future.delayed(widget.pause);
      if (!_running) {
        break;
      }
      _controller.jumpTo(0);
    }
  }

  void _setShouldScroll(bool value) {
    if (_shouldScroll == value) {
      return;
    }
    _shouldScroll = value;
    if (!_shouldScroll) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    } else {
      _startLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final shouldScroll = painter.width > constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _setShouldScroll(shouldScroll);
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
            alignment: Alignment.centerLeft,
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
