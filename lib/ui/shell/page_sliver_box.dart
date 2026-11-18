import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shell/page_sliver_padding.dart';

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
