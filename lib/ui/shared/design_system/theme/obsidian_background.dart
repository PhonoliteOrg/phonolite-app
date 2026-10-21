import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianBackground extends StatelessWidget {
  final Widget child;

  const ObsidianBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [ObsidianPalette.obsidian.withByteOpacity(0.0), Colors.black],
                radius: 1.1,
                center: Alignment.topCenter,
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
