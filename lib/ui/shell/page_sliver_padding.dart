import 'package:flutter/material.dart';

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
