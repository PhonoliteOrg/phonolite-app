import 'package:flutter/material.dart';

/// Scroll clearance for the playback controls overlaid on the page viewport.
class PlaybackContentInset extends InheritedWidget {
  const PlaybackContentInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PlaybackContentInset>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(PlaybackContentInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// Keeps the last row scrollable above the playbar without shrinking the view.
class SliverPlaybackInset extends StatelessWidget {
  const SliverPlaybackInset({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: PlaybackContentInset.bottomOf(context)),
  );
}
