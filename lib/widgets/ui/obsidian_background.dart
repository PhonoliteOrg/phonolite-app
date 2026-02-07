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
        const Positioned.fill(child: _Scanlines()),
      ],
    );
  }
}

class _Scanlines extends StatelessWidget {
  const _Scanlines();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanlinePainter(),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..strokeWidth = 1;
    const spacing = 6.0;
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
