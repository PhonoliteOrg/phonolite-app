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
