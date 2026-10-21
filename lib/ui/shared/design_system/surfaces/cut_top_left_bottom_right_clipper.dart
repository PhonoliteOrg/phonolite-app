import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_geometry.dart';

class CutTopLeftBottomRightClipper extends CustomClipper<Path> {
  final double cut;

  const CutTopLeftBottomRightClipper({required this.cut});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: cut, topRight: false, bottomLeft: false);

  @override
  bool shouldReclip(covariant CutTopLeftBottomRightClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}
