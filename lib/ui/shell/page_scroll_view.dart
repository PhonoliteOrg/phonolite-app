import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/sliver_page_top_inset.dart';
import 'package:phonolite_app/ui/shell/sliver_playback_inset.dart';

/// Standard scrolling page assembly. Pages supply only their content slivers.
class PageScrollView extends StatelessWidget {
  final List<Widget> slivers;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final bool includeTopInset;
  final bool includeBottomInset;

  /// Reserves the system area for pinned controls while content scrolls behind it.
  final bool pinTopInset;

  const PageScrollView({
    super.key,
    required this.slivers,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.includeTopInset = true,
    this.includeBottomInset = true,
    this.pinTopInset = false,
  });

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: controller,
    physics: physics,
    keyboardDismissBehavior: keyboardDismissBehavior,
    slivers: [
      if (includeTopInset) SliverPageTopInset(pinned: pinTopInset),
      ...slivers,
      if (includeBottomInset) const SliverPlaybackInset(),
    ],
  );
}
