import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/obsidian_hover_card.dart';
import 'album_art.dart';
import 'album_labels.dart';
import 'card_image_frame.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final isMobile = MediaQuery.of(context).size.width < 640;
    final boost = isMobile ? 1.2 : 1.0;
    double s(double value) => value * scale;
    double t(double value) => value * scale * boost;
    return ObsidianHoverCard(
      cut: s(20),
      padding: EdgeInsets.all(s(14)),
      onTap: onTap,
      splashColor: accentGold.withOpacity(0.2),
      childBuilder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final minImageSize = s(80.0) * boost;
          final maxImageSize = math.min(
            albumPortraitSize * scale * boost,
            constraints.maxWidth,
          );
          final reservedTextHeight = t(74.0);
          final availableForImage = (constraints.maxHeight - reservedTextHeight)
              .clamp(minImageSize, albumPortraitSize * scale * boost);
          final imageSize = math.min(maxImageSize, availableForImage);

          return Column(
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
              SizedBox(height: s(4)),
              Text(
                albumYearLabel(album),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: t(11),
                  letterSpacing: s(1.1),
                ),
              ),
              SizedBox(height: s(4)),
              const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }
}
