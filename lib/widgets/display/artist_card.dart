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
  });

  final Artist artist;
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
      padding: EdgeInsets.all(s(16)),
      onTap: onTap,
      splashColor: accentGold.withOpacity(0.2),
      childBuilder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
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
            '${artist.albumCount} ALBUMS',
            textAlign: TextAlign.center,
            style: GoogleFonts.rajdhani(
              color: Colors.white54,
              fontSize: t(12),
              letterSpacing: s(1.4),
            ),
          ),
        ],
      ),
    );
  }
}
