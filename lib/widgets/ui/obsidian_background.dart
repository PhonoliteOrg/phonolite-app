import 'package:flutter/material.dart';

import 'obsidian_theme.dart';

class ObsidianBackground extends StatelessWidget {
  const ObsidianBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  ObsidianPalette.obsidian.withOpacity(0.0),
                  Colors.black,
                ],
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
