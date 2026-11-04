import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/pointer_interaction.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/chamfer_geometry.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/blur.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class PlaybackHudPlayButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const PlaybackHudPlayButton({super.key, required this.icon, required this.onPressed, this.size = 54});

  @override
  State<PlaybackHudPlayButton> createState() => PlaybackHudPlayButtonState();
}

class PlaybackHudPlayButtonState extends State<PlaybackHudPlayButton> with PointerInteraction<PlaybackHudPlayButton> {
  static const Duration _transition = Duration(milliseconds: 200);

  @override
  bool get interactionEnabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final scaleFactor = widget.size / 54;
    final baseSize = s(widget.size);
    final iconSize = baseSize * 0.48;
    final borderWidth = s(1.5 * scaleFactor);
    final enabled = widget.onPressed != null;
    final highlight = enabled && (hovered || pressed);
    final double glowOpacity;

    if (enabled) {
      glowOpacity = highlight ? 0.7 : 0.35;
    } else {
      glowOpacity = 0.0;
    }

    final baseColor = enabled ? ObsidianPalette.gold : ObsidianPalette.textMuted.withByteOpacity(0.28);
    final idleFill = enabled
        ? ObsidianPalette.obsidianElevated.withValues(alpha: 0.72)
        : ObsidianPalette.obsidianElevated.withValues(alpha: 0.4);
    final idleIcon = enabled ? ObsidianPalette.gold : ObsidianPalette.textMuted.withByteOpacity(0.75);

    return pointerRegion(
      onTap: widget.onPressed,

      child: SizedBox(
        width: baseSize,
        height: baseSize,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: glowOpacity),
          duration: _transition,
          curve: Curves.easeOut,
          builder: (context, animatedGlow, _) {
            return CustomPaint(
              painter: animatedGlow > 0
                  ? PlaybackHudPlayButtonBorderPainter(
                      color: ObsidianPalette.gold.withValues(alpha: animatedGlow),
                      width: borderWidth,
                      blurSigma: s(8 * scaleFactor),
                    )
                  : null,
              foregroundPainter: PlaybackHudPlayButtonBorderPainter(color: baseColor, width: borderWidth),
              child: ClipPath(
                clipper: const PlaybackOctagonClipper(cutFraction: 0.3),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: highlight ? ObsidianPalette.gold.withValues(alpha: 0.75) : idleFill),
                  duration: _transition,
                  curve: Curves.easeOut,
                  builder: (context, animatedFill, __) {
                    final fill = animatedFill ?? idleFill;

                    return maybeBlur(
                      sigma: s(12 * scaleFactor),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color.alphaBlend(Colors.white.withValues(alpha: 0.06), fill), fill],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: highlight ? Colors.black : idleIcon),
                          duration: _transition,
                          curve: Curves.easeOut,
                          builder: (context, animatedIconColor, ___) {
                            return Icon(widget.icon, color: animatedIconColor, size: iconSize);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PlaybackOctagonClipper extends CustomClipper<Path> {
  final double cutFraction;
  final double inset;

  const PlaybackOctagonClipper({required this.cutFraction, this.inset = 0});

  @override
  Path getClip(Size size) {
    final inset = this.inset.clamp(0.0, size.shortestSide / 2);
    final rect = (Offset.zero & size).deflate(inset);

    if (rect.isEmpty) {
      return Path();
    }

    final outerCut = (size.shortestSide * cutFraction).clamp(0.0, size.shortestSide / 2);
    // Offset diagonals by the same perpendicular distance as straight edges.
    final cut = (outerCut - (2 - math.sqrt2) * inset).clamp(0.0, rect.shortestSide / 2);

    return chamferedRectPath(rect, cut: cut);
  }

  @override
  bool shouldReclip(covariant PlaybackOctagonClipper oldClipper) {
    return oldClipper.cutFraction != cutFraction || oldClipper.inset != inset;
  }
}

class PlaybackHudPlayButtonBorderPainter extends CustomPainter {
  final Color color;
  final double width;
  final double blurSigma;

  const PlaybackHudPlayButtonBorderPainter({required this.color, required this.width, this.blurSigma = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = const PlaybackOctagonClipper(cutFraction: 0.3).getClip(size);
    final inner = PlaybackOctagonClipper(cutFraction: 0.3, inset: width).getClip(size);

    final ring = Path();
    ring.fillType = PathFillType.evenOdd;
    ring.addPath(outer, Offset.zero);
    ring.addPath(inner, Offset.zero);

    final paint = Paint();
    paint.color = color;

    if (blurSigma > 0) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blurSigma);
    }

    // Paint over the full glass fill so the inner edge cannot expose a seam.
    canvas.drawPath(ring, paint);
  }

  @override
  bool shouldRepaint(covariant PlaybackHudPlayButtonBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.width != width || oldDelegate.blurSigma != blurSigma;
  }
}
