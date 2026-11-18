import 'package:flutter/material.dart';

/// Scroll clearance for system UI and controls overlaid on the page viewport.
class PlaybackContentInset extends InheritedWidget {
  final double bottom;
  final double top;

  const PlaybackContentInset({super.key, required this.bottom, required super.child, this.top = 0});

  static double topOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackContentInset>()?.top ?? 0;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackContentInset>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(PlaybackContentInset oldWidget) => bottom != oldWidget.bottom || top != oldWidget.top;
}
