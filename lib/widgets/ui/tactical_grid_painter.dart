import 'package:flutter/material.dart';

class TacticalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = Colors.white.withOpacity(0.01)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1;
    const minorStep = 28.0;
    const majorStep = minorStep * 4;

    for (double x = 0; x <= size.width; x += minorStep) {
      final paint = (x % majorStep == 0) ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += minorStep) {
      final paint = (y % majorStep == 0) ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant TacticalGridPainter oldDelegate) => false;
}
