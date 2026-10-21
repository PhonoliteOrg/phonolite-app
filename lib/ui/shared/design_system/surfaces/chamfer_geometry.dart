import 'package:flutter/widgets.dart';

/// The shared geometry behind chamfered surfaces, clippers and borders.
/// Coordinate-based callers can use the same shape for inset border paths.
Path chamferedRectPath(
  Rect rect, {
  required double cut,
  bool topLeft = true,
  bool topRight = true,
  bool bottomRight = true,
  bool bottomLeft = true,
}) {
  final corner = cut.clamp(0.0, rect.shortestSide / 2);
  final tl = topLeft ? corner : 0.0;
  final tr = topRight ? corner : 0.0;
  final br = bottomRight ? corner : 0.0;
  final bl = bottomLeft ? corner : 0.0;

  final path = Path();
  path.moveTo(rect.left + tl, rect.top);
  path.lineTo(rect.right - tr, rect.top);
  path.lineTo(rect.right, rect.top + tr);
  path.lineTo(rect.right, rect.bottom - br);
  path.lineTo(rect.right - br, rect.bottom);
  path.lineTo(rect.left + bl, rect.bottom);
  path.lineTo(rect.left, rect.bottom - bl);
  path.lineTo(rect.left, rect.top + tl);
  path.close();

  return path;
}
