import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_geometry.dart';

class ChamferedClipper extends CustomClipper<Path> {
  final double cut;

  const ChamferedClipper({required this.cut});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: cut);

  @override
  bool shouldReclip(covariant ChamferedClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class CutTopLeftClipper extends CustomClipper<Path> {
  final double cut;

  const CutTopLeftClipper({required this.cut});

  @override
  Path getClip(Size size) =>
      chamferedRectPath(Offset.zero & size, cut: cut, topRight: false, bottomRight: false, bottomLeft: false);

  @override
  bool shouldReclip(covariant CutTopLeftClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class CutBottomRightClipper extends CustomClipper<Path> {
  final double cut;

  const CutBottomRightClipper({required this.cut});

  @override
  Path getClip(Size size) =>
      chamferedRectPath(Offset.zero & size, cut: cut, topLeft: false, topRight: false, bottomLeft: false);

  @override
  bool shouldReclip(covariant CutBottomRightClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class ChamferedBorderPainter extends CustomPainter {
  final double cut;
  final Color color;
  final double strokeWidth;

  const ChamferedBorderPainter({required this.cut, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final path = ChamferedClipper(cut: cut).getClip(size);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = strokeWidth;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ChamferedBorderPainter oldDelegate) {
    return oldDelegate.cut != cut || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

class DiagonalChamferClipper extends CustomClipper<Path> {
  final double cut;

  const DiagonalChamferClipper({required this.cut});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: cut, topRight: false, bottomLeft: false);

  @override
  bool shouldReclip(covariant DiagonalChamferClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class DiagonalChamferedBorderPainter extends CustomPainter {
  final double cut;
  final Color color;
  final double strokeWidth;

  const DiagonalChamferedBorderPainter({required this.cut, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final path = DiagonalChamferClipper(cut: cut).getClip(size);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = strokeWidth;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DiagonalChamferedBorderPainter oldDelegate) {
    return oldDelegate.cut != cut || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
