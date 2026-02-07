import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'blur.dart';

class GlassChamfered extends StatelessWidget {
  const GlassChamfered({
    super.key,
    required this.cut,
    required this.child,
    this.padding,
    this.onTap,
  });

  final double cut;
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ClipPath(
      clipper: ChamferedClipper(cut: cut),
      child: maybeBlur(
        sigma: 16,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

class ChamferedButton extends StatelessWidget {
  const ChamferedButton({
    super.key,
    required this.cut,
    required this.size,
    required this.icon,
  });

  final double cut;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ChamferedClipper(cut: cut),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: accentGold,
        ),
        child: Icon(icon, color: Colors.black),
      ),
    );
  }
}

class ChamferedClipper extends CustomClipper<Path> {
  const ChamferedClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(covariant ChamferedClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class CutTopLeftClipper extends CustomClipper<Path> {
  const CutTopLeftClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(covariant CutTopLeftClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class CutBottomRightClipper extends CustomClipper<Path> {
  const CutBottomRightClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0.0, size.shortestSide / 2);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CutBottomRightClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class ChamferedBorderPainter extends CustomPainter {
  const ChamferedBorderPainter({
    required this.cut,
    required this.color,
    required this.strokeWidth,
  });

  final double cut;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ChamferedClipper(cut: cut).getClip(size);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ChamferedBorderPainter oldDelegate) {
    return oldDelegate.cut != cut ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class DiagonalChamferClipper extends CustomClipper<Path> {
  const DiagonalChamferClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0.0, size.shortestSide / 2);
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
  bool shouldReclip(covariant DiagonalChamferClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class DiagonalChamferedBorderPainter extends CustomPainter {
  const DiagonalChamferedBorderPainter({
    required this.cut,
    required this.color,
    required this.strokeWidth,
  });

  final double cut;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = DiagonalChamferClipper(cut: cut).getClip(size);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DiagonalChamferedBorderPainter oldDelegate) {
    return oldDelegate.cut != cut ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
