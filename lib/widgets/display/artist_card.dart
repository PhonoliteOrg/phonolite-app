import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_hover_card.dart';
import 'artist_avatar.dart';
import 'card_image_frame.dart';

class ArtistCard extends StatelessWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  final Artist artist;
  final String? coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final bool isDeleting;
  final VoidCallback? onSelectionToggle;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final isMobile = MediaQuery.of(context).size.width < 640;
    final boost = isMobile ? 1.2 : 1.0;
    double s(double value) => value * scale;
    double t(double value) => value * scale * boost;
    final canInteract = selectable && !isDeleting;
    final effectiveOnTap = selectionMode
        ? canInteract
              ? onSelectionToggle
              : null
        : isDeleting
        ? null
        : onTap;
    final card = ObsidianHoverCard(
      padding: EdgeInsets.all(s(14)),
      onTap: effectiveOnTap,
      splashColor: accentGold.withValues(alpha: 0.2),
      childBuilder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final imageSize = math.min(
            t(170),
            math.max(
              0.0,
              math.min(
                constraints.maxWidth - 4,
                constraints.maxHeight - t(42) - 4,
              ),
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CardImageFrame(
                hovered: hovered,
                child: ArtistAvatar(
                  name: artist.name,
                  size: imageSize,
                  imageUrl: coverUrl,
                  headers: headers,
                  fit: BoxFit.contain,
                  paddingFraction: 0,
                ),
              ),
              SizedBox(height: s(12)),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontSize: t(18),
                  fontWeight: FontWeight.w700,
                  letterSpacing: s(1.1),
                ),
              ),
            ],
          );

          final fittedContent = AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: isDeleting ? 0.45 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(width: constraints.maxWidth, child: content),
            ),
          );

          if (!isDeleting) {
            return fittedContent;
          }

          return Stack(
            children: [
              fittedContent,
              Positioned(
                right: s(4),
                bottom: s(4),
                child: SizedBox(
                  width: s(24),
                  height: s(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentGold,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return Semantics(
      selected: selectionMode ? selected : null,
      enabled: selectionMode ? effectiveOnTap != null : null,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selectionMode
              ? Border.all(
                  color: selected ? accentGold : Colors.grey,
                  width: 1.5,
                )
              : null,
        ),
        child: card,
      ),
    );
  }
}
