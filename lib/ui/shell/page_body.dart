import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/playback_content_inset.dart';

enum PageToolbarPlacement { scrolling, fixed }

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

/// The single toolbar/body layout implementation used by the base page.
/// Standalone presentation composites may reuse it without becoming pages.
class PageLayout extends StatelessWidget {
  final PageBody body;
  final Widget? navbar;
  final PageToolbarPlacement toolbarPlacement;
  final EdgeInsetsGeometry navbarPadding;

  const PageLayout({
    super.key,
    required this.body,
    this.navbar,
    this.toolbarPlacement = PageToolbarPlacement.scrolling,
    this.navbarPadding = const EdgeInsets.fromLTRB(20, 16, 20, 12),
  });

  Widget _body(BuildContext context, {Widget? scrollingNavbar, bool fixedNavbar = false}) {
    final direction = Directionality.of(context);
    var padding = body.padding.resolve(direction);

    if (fixedNavbar && body is! BoxPageBody) {
      padding = padding.copyWith(top: 0);
    }

    final top = body.includePlaybackInsets && !fixedNavbar ? PlaybackContentInset.topOf(context) : 0.0;
    final bottom = body.includePlaybackInsets ? PlaybackContentInset.bottomOf(context) : 0.0;
    final toolbar = scrollingNavbar == null ? null : Padding(padding: navbarPadding, child: scrollingNavbar);

    return switch (body) {
      BoxPageBody(:final child) => Padding(
        padding: padding + EdgeInsets.only(top: top, bottom: bottom),
        child: child,
      ),
      ScrollPageBody(
        :final child,
        :final controller,
        :final physics,
        :final keyboardDismissBehavior,
        :final includeKeyboardInset,
      ) =>
        SingleChildScrollView(
          controller: controller,
          physics: physics,
          keyboardDismissBehavior: keyboardDismissBehavior,
          padding:
              padding +
              EdgeInsets.only(
                top: top,
                bottom: bottom + (includeKeyboardInset ? MediaQuery.viewInsetsOf(context).bottom : 0),
              ),
          child: toolbar == null
              ? child
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [toolbar, child]),
        ),
      SliverPageBody(
        :final slivers,
        :final controller,
        :final physics,
        :final keyboardDismissBehavior,
        :final pinTopInset,
      ) =>
        PageScrollView(
          controller: controller,
          physics: physics,
          keyboardDismissBehavior: keyboardDismissBehavior,
          includeTopInset: body.includePlaybackInsets && !fixedNavbar,
          includeBottomInset: body.includePlaybackInsets,
          pinTopInset: pinTopInset,
          slivers: _slivers(slivers, toolbar, padding),
        ),
    };
  }

  List<Widget> _slivers(List<Widget> content, Widget? toolbar, EdgeInsets padding) {
    final slivers = [if (toolbar != null) SliverToBoxAdapter(child: toolbar), ...content];

    return padding == EdgeInsets.zero
        ? slivers
        : [
            SliverPadding(
              padding: padding,
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ];
  }

  @override
  Widget build(BuildContext context) {
    final navbar = this.navbar;
    if (navbar == null) {
      return _body(context);
    }

    if (toolbarPlacement == PageToolbarPlacement.scrolling) {
      if (body is BoxPageBody) {
        throw FlutterError(
          'A scrolling page toolbar requires PageBody.scroll or '
          'PageBody.slivers. Use PageToolbarPlacement.fixed for a bounded '
          'PageBody.box.',
        );
      }

      return _body(context, scrollingNavbar: navbar);
    }

    final commonPadding = body is BoxPageBody ? EdgeInsets.zero : body.padding.resolve(Directionality.of(context));
    final toolbarInsets =
        navbarPadding.resolve(Directionality.of(context)) +
        EdgeInsets.fromLTRB(commonPadding.left, commonPadding.top, commonPadding.right, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (body.includePlaybackInsets) SizedBox(height: PlaybackContentInset.topOf(context)),
        Padding(padding: toolbarInsets, child: navbar),
        Expanded(child: _body(context, fixedNavbar: true)),
      ],
    );
  }
}
