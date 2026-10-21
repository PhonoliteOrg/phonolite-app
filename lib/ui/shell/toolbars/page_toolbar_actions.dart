import 'package:flutter/material.dart';

/// Wrapping page actions share alignment while their owners supply the actions.
class PageToolbarActions extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const PageToolbarActions({super.key, required this.children, this.spacing = 10, this.runSpacing = 10});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: spacing,
    runSpacing: runSpacing,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

/// Responsive dimensions for the compact icon action family in page headers.
class PageToolbarActionLayout {
  static const double regularIconSize = 26;

  final bool compact;

  const PageToolbarActionLayout._(this.compact);

  factory PageToolbarActionLayout.of(BuildContext context) =>
      PageToolbarActionLayout._(MediaQuery.sizeOf(context).width < 640);

  double get iconSize => compact ? 22 : regularIconSize;

  double get spacing => compact ? 4 : 10;

  double get runSpacing => compact ? 4 : 8;
}
