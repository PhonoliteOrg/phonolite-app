import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_hover_card.dart';
import 'album_art.dart';
import 'card_image_frame.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
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
      onLongPress: selectionMode || isDeleting ? null : onLongPress,
      splashColor: accentGold.withValues(alpha: 0.2),
      childBuilder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final minImageSize = s(80.0) * boost;
          final maxImageSize = math.min(
            albumPortraitSize * scale * boost,
            constraints.maxWidth,
          );
          final reservedTextHeight = t(48.0);
          final availableForImage = (constraints.maxHeight - reservedTextHeight)
              .clamp(minImageSize, albumPortraitSize * scale * boost);
          final imageSize = math.min(maxImageSize, availableForImage);
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CardImageFrame(
                hovered: hovered,
                borderRadius: BorderRadius.zero,
                child: AlbumArt(
                  title: album.title,
                  size: imageSize,
                  imageUrl: coverUrl,
                  headers: headers,
                ),
              ),
              SizedBox(height: s(14)),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontSize: t(16),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );

          final effectiveContent = AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: isDeleting ? 0.45 : 1,
            child: content,
          );
          return Stack(
            fit: StackFit.passthrough,
            children: [
              effectiveContent,
              if (isDeleting)
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
