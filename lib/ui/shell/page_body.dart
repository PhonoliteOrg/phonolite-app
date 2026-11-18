import 'package:flutter/material.dart';

/// Content supplied to the page frame, without constructing its toolbar layout.
sealed class PageBody {
  final EdgeInsetsGeometry padding;
  final bool includePlaybackInsets;

  const PageBody({required this.padding, required this.includePlaybackInsets});

  /// A bounded body, including flex layouts or a shell with its own viewport.
  const factory PageBody.box({required Widget child, EdgeInsetsGeometry padding, bool includePlaybackInsets}) =
      BoxPageBody;

  /// A box body that scrolls together with its toolbar by default.
  const factory PageBody.scroll({
    required Widget child,
    EdgeInsetsGeometry padding,
    ScrollController? controller,
    ScrollPhysics? physics,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior,
    bool includePlaybackInsets,
    bool includeKeyboardInset,
  }) = ScrollPageBody;

  /// Lazy content slivers; the frame adds toolbar and overlay clearance.
  const factory PageBody.slivers({
    required List<Widget> slivers,
    EdgeInsetsGeometry padding,
    ScrollController? controller,
    ScrollPhysics? physics,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior,
    bool includePlaybackInsets,
    bool pinTopInset,
  }) = SliverPageBody;
}

final class BoxPageBody extends PageBody {
  final Widget child;

  const BoxPageBody({required this.child, super.padding = EdgeInsets.zero, super.includePlaybackInsets = false});
}

final class ScrollPageBody extends PageBody {
  final Widget child;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final bool includeKeyboardInset;

  const ScrollPageBody({
    required this.child,
    super.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    super.includePlaybackInsets = true,
    this.includeKeyboardInset = false,
  });
}

final class SliverPageBody extends PageBody {
  final List<Widget> slivers;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final bool pinTopInset;

  const SliverPageBody({
    required this.slivers,
    super.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    super.includePlaybackInsets = true,
    this.pinTopInset = false,
  });
}
