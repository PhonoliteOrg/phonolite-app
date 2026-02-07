import 'package:flutter/material.dart';

import 'blur.dart';
import 'obsidian_shapes.dart';
import 'obsidian_theme.dart';

enum ObsidianButtonStyle { glass, subtle }

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.cut = 16,
    this.blur = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.gradient,
    this.borderColor,
    this.shadowColor,
  });

  final Widget child;
  final double cut;
  final double blur;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final resolvedGradient = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.01),
          ],
        );
    final border = borderColor ?? ObsidianPalette.border.withOpacity(0.7);
    final shadow = shadowColor ?? Colors.black.withOpacity(0.6);

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipPath(
        clipper: CyberClipper(cut: cut),
        child: maybeBlur(
          sigma: blur,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: resolvedGradient,
              border: Border.all(color: border),
            ),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class ObsidianIconButton extends StatelessWidget {
  const ObsidianIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.isActive = false,
    this.size = 46,
    this.cut = 12,
    this.style = ObsidianButtonStyle.glass,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;
  final double size;
  final double cut;
  final ObsidianButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? ObsidianPalette.textMuted.withOpacity(0.4)
        : isActive
            ? ObsidianPalette.gold
            : ObsidianPalette.textMuted;
    final gradient = isActive && enabled && style == ObsidianButtonStyle.glass
        ? LinearGradient(
            colors: [
              ObsidianPalette.gold.withOpacity(0.2),
              ObsidianPalette.gold.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    final panel = style == ObsidianButtonStyle.glass
        ? GlassPanel(
            cut: cut,
            padding: EdgeInsets.zero,
            gradient: gradient,
            shadowColor:
                enabled ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.2),
            child: _buildInk(color),
          )
        : ClipPath(
            clipper: CyberClipper(cut: cut),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                border: Border.all(
                  color: enabled
                      ? ObsidianPalette.border.withOpacity(0.6)
                      : ObsidianPalette.border.withOpacity(0.25),
                ),
              ),
              child: _buildInk(color),
            ),
          );

    return SizedBox(
      width: size,
      height: size,
      child: panel,
    );
  }

  Widget _buildInk(Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class ObsidianHudIconButton extends StatelessWidget {
  const ObsidianHudIconButton({
    super.key,
    required this.icon,
    this.isActive = false,
    this.size = 26,
    this.onPressed,
  });

  final IconData icon;
  final bool isActive;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _HoverHudIconButton(
      icon: icon,
      size: size,
      isActive: isActive,
      onPressed: onPressed,
    );
  }
}

class _HoverHudIconButton extends StatefulWidget {
  const _HoverHudIconButton({
    required this.icon,
    required this.size,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  State<_HoverHudIconButton> createState() => _HoverHudIconButtonState();
}

class _HoverHudIconButtonState extends State<_HoverHudIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  static const _transition = Duration(milliseconds: 200);

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isActive || _hovered || _pressed;
    final glowOpacity = _hovered ? 0.7 : (widget.isActive ? 0.35 : 0.0);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: glowOpacity),
            duration: _transition,
            curve: Curves.easeOut,
            builder: (context, animatedGlow, child) {
              return TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: highlight ? ObsidianPalette.gold : ObsidianPalette.textMuted,
                ),
                duration: _transition,
                curve: Curves.easeOut,
                builder: (context, animatedColor, _) {
                  return Icon(
                    widget.icon,
                    color: animatedColor,
                    size: widget.size,
                    shadows: [
                      if (animatedGlow > 0)
                        Shadow(
                          color: ObsidianPalette.gold.withOpacity(animatedGlow),
                          blurRadius: 10,
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class ObsidianSectionHeader extends StatelessWidget {
  const ObsidianSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Color(0xFF9A9A9A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: Text(
                  title,
                  style: textTheme.headlineLarge?.copyWith(
                    letterSpacing: 1.2,
                    height: 1.05,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: textTheme.labelLarge?.copyWith(
                    color: ObsidianPalette.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class ObsidianPlayButton extends StatefulWidget {
  const ObsidianPlayButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<ObsidianPlayButton> createState() => _ObsidianPlayButtonState();
}

class _ObsidianPlayButtonState extends State<ObsidianPlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onPressed != null;
    final bg = _hovered
        ? ObsidianPalette.gold
        : ObsidianPalette.gold.withOpacity(0.08);
    final iconColor = _hovered ? Colors.black : ObsidianPalette.gold;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: CustomPaint(
            painter: _OctagonBorderPainter(
              color: ObsidianPalette.gold.withOpacity(active ? 1.0 : 0.4),
              hovered: _hovered,
            ),
            child: ClipPath(
              clipper: OctagonClipper(corner: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  boxShadow: _hovered
                      ? [
                          BoxShadow(
                            color: ObsidianPalette.goldSoft,
                            blurRadius: 16,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: ObsidianPalette.goldSoft.withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ],
                ),
                child: Center(
                  child: Icon(widget.icon, color: iconColor, size: 28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OctagonBorderPainter extends CustomPainter {
  _OctagonBorderPainter({required this.color, required this.hovered});

  final Color color;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(hovered ? 0.4 : 1.0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = OctagonClipper(corner: 12).getClip(size);
    canvas.drawPath(path, paint);

    if (!hovered) {
      final accent = Paint()
        ..color = color
        ..strokeWidth = 2;
      final inset = 6.0;
      canvas.drawLine(
        Offset(inset, 0),
        Offset(size.width - inset, 0),
        accent,
      );
      canvas.drawLine(
        Offset(inset, size.height),
        Offset(size.width - inset, size.height),
        accent,
      );
      canvas.drawLine(
        Offset(0, inset),
        Offset(0, size.height - inset),
        accent,
      );
      canvas.drawLine(
        Offset(size.width, inset),
        Offset(size.width, size.height - inset),
        accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OctagonBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.hovered != hovered;
  }
}

class ObsidianNavIcon extends StatelessWidget {
  const ObsidianNavIcon({
    super.key,
    required this.icon,
    required this.isSelected,
  });

  final Widget icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected
        ? ObsidianPalette.gold.withOpacity(0.1)
        : Colors.white.withOpacity(0.03);
    final border =
        isSelected ? ObsidianPalette.gold : Colors.white.withOpacity(0.05);
    final iconColor =
        isSelected ? ObsidianPalette.gold : ObsidianPalette.textMuted;
    final shadow = isSelected
        ? [
            BoxShadow(
              color: ObsidianPalette.goldSoft,
              blurRadius: 15,
            ),
          ]
        : const <BoxShadow>[];

    return ClipPath(
      clipper: const CutTopLeftBottomRightClipper(cut: 10),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border),
          boxShadow: shadow,
        ),
        child: ClipPath(
          clipper: const CutTopLeftBottomRightClipper(cut: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: null,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: IconTheme(
                  data: IconThemeData(color: iconColor),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CutTopLeftBottomRightClipper extends CustomClipper<Path> {
  const CutTopLeftBottomRightClipper({required this.cut});

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
  bool shouldReclip(covariant CutTopLeftBottomRightClipper oldClipper) {
    return oldClipper.cut != cut;
  }
}

class ObsidianCard extends StatelessWidget {
  const ObsidianCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      cut: 18,
      padding: padding,
      child: child,
    );
  }
}
