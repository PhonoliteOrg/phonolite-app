import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_geometry.dart';

class ChamferClipper extends CustomClipper<Path> {
  final double cutSize;

  const ChamferClipper({required this.cutSize});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: cutSize, topRight: false, bottomLeft: false);

  @override
  bool shouldReclip(covariant ChamferClipper oldClipper) {
    return oldClipper.cutSize != cutSize;
  }
}
