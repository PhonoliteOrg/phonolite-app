import 'package:flutter/material.dart';

import '../ui/dismissible_selection_area.dart';
import '../ui/obsidian_background.dart';
import '../ui/obsidian_theme.dart';
import 'obsidian_scale.dart';

/// Applies responsive sizing below MaterialApp, without animating the theme or
/// rebuilding the app's routing configuration on every window resize.
class ObsidianViewport extends StatelessWidget {
  const ObsidianViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = ObsidianScale.compute(constraints.maxWidth);
        return Theme(
          data: ObsidianTheme.build(scale: scale),
          child: SelectionDismissLayer(
            child: ObsidianBackground(
              child: ObsidianScale(scale: scale, child: child),
            ),
          ),
        );
      },
    );
  }
}
