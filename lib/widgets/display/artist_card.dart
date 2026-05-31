import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_hover_card.dart';
import 'album_labels.dart';
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
    return ObsidianHoverCard(
      cut: s(20),
      padding: EdgeInsets.all(s(16)),
      onTap: effectiveOnTap,
      splashColor: accentGold.withValues(alpha: 0.2),
      childBuilder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              CardImageFrame(
                hovered: hovered,
                child: ArtistAvatar(
                  name: artist.name,
                  size: t(120),
                  imageUrl: coverUrl,
                  headers: headers,
                  fit: BoxFit.contain,
                  paddingFraction: 0,
                ),
              ),
              SizedBox(height: s(16)),
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
              SizedBox(height: s(12)),
              Text(
                artistDetailLabel(artist).toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: t(12),
                  letterSpacing: s(1.4),
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

          if (!selectionMode && !isDeleting) {
            return fittedContent;
          }

          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: accentGold, width: 1.5),
                    ),
                  ),
                ),
              ),
              fittedContent,
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
              Positioned(
                top: 0,
                right: 0,
                child: selectionMode
                    ? Checkbox(
                        value: selected,
                        onChanged: canInteract && onSelectionToggle != null
                            ? (_) => onSelectionToggle!()
                            : null,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: accentGold,
                        side: BorderSide(
                          color: canInteract ? Colors.white70 : Colors.white24,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }
}
