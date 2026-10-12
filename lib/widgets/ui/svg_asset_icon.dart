import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A bundled SVG icon that follows the surrounding icon theme.
class SvgAssetIcon extends StatelessWidget {
  const SvgAssetIcon({super.key, required this.assetName, this.size});

  final String assetName;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 24;
    final color = theme.color ?? const Color(0xFF000000);
    final icon = _picture(
      dimension,
      color.withValues(alpha: color.a * (theme.opacity ?? 1)),
    );
    final shadows = theme.shadows ?? const <Shadow>[];
    if (shadows.isEmpty) {
      return icon;
    }

    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final shadow in shadows)
            Transform.translate(
              offset: shadow.offset,
              child: ImageFiltered(
                enabled: shadow.blurRadius > 0,
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: shadow.blurSigma,
                  sigmaY: shadow.blurSigma,
                ),
                child: _picture(dimension, shadow.color),
              ),
            ),
          icon,
        ],
      ),
    );
  }

  SvgPicture _picture(double dimension, Color color) {
    return SvgPicture.asset(
      assetName,
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
