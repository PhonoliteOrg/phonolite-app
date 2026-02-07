import 'package:flutter/material.dart';

class ChamferClipper extends CustomClipper<Path> {
  const ChamferClipper({required this.cutSize});

  final double cutSize;

  @override
  Path getClip(Size size) {
    final c = cutSize.clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(covariant ChamferClipper oldClipper) {
    return oldClipper.cutSize != cutSize;
  }
}
