import 'package:flutter/widgets.dart';

class CyberClipper extends CustomClipper<Path> {
  CyberClipper({this.cut = 16});

  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut.clamp(0, size.shortestSide / 2).toDouble();
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
  bool shouldReclip(CyberClipper oldClipper) => oldClipper.cut != cut;
}

class OctagonClipper extends CustomClipper<Path> {
  OctagonClipper({this.corner = 10});

  final double corner;

  @override
  Path getClip(Size size) {
    final c = corner.clamp(0, size.shortestSide / 2).toDouble();
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
  bool shouldReclip(OctagonClipper oldClipper) => oldClipper.corner != corner;
}

class CyberShapeBorder extends ShapeBorder {
  const CyberShapeBorder({this.cut = 16, this.side = BorderSide.none});

  final double cut;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) {
    return CyberShapeBorder(cut: cut * t, side: side.scale(t));
  }

  Path _buildPath(Rect rect) {
    final c = cut.clamp(0.0, rect.shortestSide / 2);
    return Path()
      ..moveTo(rect.left + c, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - c, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + c)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _buildPath(rect);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.width;
    if (inset <= 0) {
      return _buildPath(rect);
    }
    return _buildPath(rect.deflate(inset));
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side == BorderSide.none) {
      return;
    }
    final paint = side.toPaint();
    canvas.drawPath(getOuterPath(rect), paint);
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => super.lerpTo(b, t);
}
