import 'package:flutter/material.dart';

import '../../core/constants.dart';

class CardImageFrame extends StatelessWidget {
  const CardImageFrame({
    super.key,
    required this.hovered,
    required this.child,
    this.borderRadius,
  });

  final bool hovered;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final saturation = hovered ? 1.0 : 0.6;
    final shadow = hovered
        ? [
            BoxShadow(
              color: accentGold.withOpacity(0.32),
              blurRadius: cardGlowBlurRadius,
              spreadRadius: 1.5,
            ),
          ]
        : const <BoxShadow>[];

    return AnimatedContainer(
      duration: const Duration(milliseconds: cardGlowAnimMs),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        boxShadow: shadow,
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(999),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
          child: child,
        ),
      ),
    );
  }
}

List<double> _saturationMatrix(double saturation) {
  final inv = 1 - saturation;
  final r = 0.213 * inv;
  final g = 0.715 * inv;
  final b = 0.072 * inv;
  return [
    r + saturation,
    g,
    b,
    0,
    0,
    r,
    g + saturation,
    b,
    0,
    0,
    r,
    g,
    b + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}
