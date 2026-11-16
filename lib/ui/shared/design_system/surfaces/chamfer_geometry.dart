import 'package:flutter/widgets.dart';

/// Builds the play/pause button outline and its inset border.
Path chamferedRectPath(Rect rect, {required double cut}) {
  final corner = cut.clamp(0.0, rect.shortestSide / 2);

  final path = Path();
  path.moveTo(rect.left + corner, rect.top);
  path.lineTo(rect.right - corner, rect.top);
  path.lineTo(rect.right, rect.top + corner);
  path.lineTo(rect.right, rect.bottom - corner);
  path.lineTo(rect.right - corner, rect.bottom);
  path.lineTo(rect.left + corner, rect.bottom);
  path.lineTo(rect.left, rect.bottom - corner);
  path.lineTo(rect.left, rect.top + corner);
  path.close();

  return path;
}
