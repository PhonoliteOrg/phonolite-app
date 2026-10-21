import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/dismissible_selection_area.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_background.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// Applies responsive sizing below MaterialApp, without animating the theme or
/// rebuilding the app's routing configuration on every window resize.
class ObsidianViewport extends StatelessWidget {
  final Widget child;

  const ObsidianViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = ObsidianScale.compute(constraints.maxWidth);

        return Theme(
          data: ObsidianTheme.build(scale: scale),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: SelectionDismissLayer(
              child: ObsidianBackground(
                child: ObsidianScale(scale: scale, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
