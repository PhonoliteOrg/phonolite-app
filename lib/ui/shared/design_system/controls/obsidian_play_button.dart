import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_shapes.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ObsidianPlayButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const ObsidianPlayButton({super.key, required this.icon, this.size = 56, this.onPressed});

  @override
  State<ObsidianPlayButton> createState() => _ObsidianPlayButtonState();
}

class _ObsidianPlayButtonState extends State<ObsidianPlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onPressed != null;
    final bg = _hovered ? ObsidianPalette.gold : ObsidianPalette.gold.withByteOpacity(0.08);
    final iconColor = _hovered ? Colors.black : ObsidianPalette.gold;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: GestureDetector(
          onTap: withButtonHaptic(widget.onPressed),
          child: CustomPaint(
            painter: _OctagonBorderPainter(
              color: ObsidianPalette.gold.withByteOpacity(active ? 1.0 : 0.4),
              hovered: _hovered,
            ),
            child: ClipPath(
              clipper: OctagonClipper(corner: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  boxShadow: _hovered
                      ? [BoxShadow(color: ObsidianPalette.goldSoft, blurRadius: 16)]
                      : [BoxShadow(color: ObsidianPalette.goldSoft.withByteOpacity(0.4), blurRadius: 10)],
                ),
                child: Center(child: Icon(widget.icon, color: iconColor, size: 28)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OctagonBorderPainter extends CustomPainter {
  final Color color;
  final bool hovered;

  _OctagonBorderPainter({required this.color, required this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color.withByteOpacity(hovered ? 0.4 : 1.0);
    paint.strokeWidth = 2;
    paint.style = PaintingStyle.stroke;

    final path = OctagonClipper(corner: 12).getClip(size);

    canvas.drawPath(path, paint);

    if (!hovered) {
      final accent = Paint();
      accent.color = color;
      accent.strokeWidth = 2;

      final inset = 6.0;

      canvas.drawLine(Offset(inset, 0), Offset(size.width - inset, 0), accent);
      canvas.drawLine(Offset(inset, size.height), Offset(size.width - inset, size.height), accent);
      canvas.drawLine(Offset(0, inset), Offset(0, size.height - inset), accent);
      canvas.drawLine(Offset(size.width, inset), Offset(size.width, size.height - inset), accent);
    }
  }

  @override
  bool shouldRepaint(covariant _OctagonBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.hovered != hovered;
  }
}
