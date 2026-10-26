import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

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

/// Shared page gutter; vertical spacing belongs to the assembled content role.
class PageSliverPadding extends StatelessWidget {
  static const double horizontalInset = 20;

  final Widget sliver;
  final double top;
  final double bottom;

  const PageSliverPadding({super.key, required this.sliver, this.top = 0, this.bottom = 0});

  @override
  Widget build(BuildContext context) =>
      SliverPadding(padding: EdgeInsets.fromLTRB(horizontalInset, top, horizontalInset, bottom), sliver: sliver);
}

/// Adapts a box component to the same page gutter and spacing contract.
class PageSliverBox extends StatelessWidget {
  final Widget child;
  final double top;
  final double bottom;
  final bool pinned;

  const PageSliverBox({super.key, required this.child, this.top = 0, this.bottom = 0, this.pinned = false});

  @override
  Widget build(BuildContext context) {
    if (pinned) {
      return PinnedHeaderSliver(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            PageSliverPadding.horizontalInset,
            top,
            PageSliverPadding.horizontalInset,
            bottom,
          ),
          child: child,
        ),
      );
    }

    return PageSliverPadding(
      top: top,
      bottom: bottom,
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}
