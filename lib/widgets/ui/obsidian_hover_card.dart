import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'blur.dart';
import 'chamfered.dart';
import 'hoverable.dart';

class ObsidianHoverCard extends StatelessWidget {
  const ObsidianHoverCard({
    super.key,
    required this.childBuilder,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.cut = 20,
    this.blurSigma = cardBackdropBlurSigma,
    this.splashColor,
  });

  final Widget Function(BuildContext context, bool hovered) childBuilder;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double cut;
  final double blurSigma;
  final Color? splashColor;

  @override
  Widget build(BuildContext context) {
    final enableHover = obsidianSupportsHover();
    return ObsidianHoverBuilder(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      enableHover: enableHover,
      builder: (context, hovered) {
        final card = ClipPath(
          clipper: DiagonalChamferClipper(cut: cut),
          child: maybeBlur(
            sigma: blurSigma,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: cardGlowAnimMs),
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(cardTopOpacity),
                    Colors.white.withOpacity(cardBottomOpacity),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: cardOverlayAnimMs),
                      opacity: hovered ? 1 : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(cardHoverOverlayTopOpacity),
                              Colors.white.withOpacity(
                                cardHoverOverlayBottomOpacity,
                              ),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: padding,
                      child: childBuilder(context, hovered),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (onTap == null) {
          return card;
        }

        if (enableHover) {
          return GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: card,
          );
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: splashColor,
            child: card,
          ),
        );
      },
    );
  }
}
