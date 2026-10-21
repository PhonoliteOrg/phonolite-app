import 'package:flutter/widgets.dart';

import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_geometry.dart';

class CyberClipper extends CustomClipper<Path> {
  final double cut;

  CyberClipper({this.cut = 16});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: cut, topRight: false, bottomLeft: false);

  @override
  bool shouldReclip(CyberClipper oldClipper) => oldClipper.cut != cut;
}

class OctagonClipper extends CustomClipper<Path> {
  final double corner;

  OctagonClipper({this.corner = 10});

  @override
  Path getClip(Size size) => chamferedRectPath(Offset.zero & size, cut: corner);

  @override
  bool shouldReclip(OctagonClipper oldClipper) => oldClipper.corner != corner;
}

class CyberShapeBorder extends ShapeBorder {
  final double cut;
  final BorderSide side;

  const CyberShapeBorder({this.cut = 16, this.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) {
    return CyberShapeBorder(cut: cut * t, side: side.scale(t));
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

  Path _buildPath(Rect rect) => chamferedRectPath(rect, cut: cut, topRight: false, bottomLeft: false);
}
