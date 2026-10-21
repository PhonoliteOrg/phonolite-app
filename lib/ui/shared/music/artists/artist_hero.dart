import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/dismissible_selection_area.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artist_avatar.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_image.dart';
import 'package:phonolite_app/ui/shared/music/formatting/album_labels.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';
import 'package:phonolite_app/ui/shared/music/media_hero_details.dart';
import 'package:phonolite_app/ui/shared/music/media_hero_frame.dart';

class ArtistHero extends StatelessWidget {
  final Artist artist;
  final String? coverUrl;
  final String? bannerUrl;
  final Map<String, String> headers;

  const ArtistHero({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.bannerUrl,
    required this.headers,
  });

  Widget _compactHeader({required String genreLine, String? summary}) {
    final hasSummary = summary != null && summary.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ArtistAvatar(
              name: artist.name,
              size: 72,
              imageUrl: coverUrl,
              headers: headers,
              fit: BoxFit.contain,
              paddingFraction: 0,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MediaHeroTitle(title: artist.name, desktopFontSize: 48, desktopLetterSpacing: 1.6),
                  const SizedBox(height: 4),
                  Text(
                    artistDetailLabel(artist, genreLimit: 0),
                    style: GoogleFonts.rajdhani(color: Colors.white54, fontSize: 11, letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (genreLine.isNotEmpty || hasSummary)
          MediaHeroDetails(
            key: ValueKey('artist-details-${artist.id}'),
            label: 'About artist',
            genres: genreLine,
            summary: summary,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final isCompact = isCompactListWidth(context);

    double s(double value) => value * scale;

    final bannerHeight = isCompact ? 140.0 : s(240);
    final bannerPath = bannerUrl?.trim();

    final summary = artist.summary?.trim().isNotEmpty == true
        ? artist.summary!
        : 'Bio unavailable. Curate this artist profile with metadata or notes.';
    final genreLine = genreBulletLine(artist.genres);
    final detailsLine = genreLine.isEmpty
        ? artistDetailLabel(artist, genreLimit: 0)
        : '${artistDetailLabel(artist, genreLimit: 0)} / $genreLine';

    return MediaHeroFrame(
      minHeight: isCompact ? 0 : s(220),
      backgroundLayers: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: bannerHeight,
          child: bannerPath == null || bannerPath.isEmpty
              ? const SizedBox.shrink()
              : ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0.0, 0.7, 1.0],
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ArtworkImage(
                    imageUrl: bannerPath,
                    headers: headers,
                    fit: BoxFit.cover,
                    placeholder: const SizedBox.shrink(),
                  ),
                ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [bgDark.withValues(alpha: 0.0), bgDark.withValues(alpha: 0.85)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
      child: isCompact
          ? _compactHeader(genreLine: genreLine, summary: artist.summary?.trim())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: s(170),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ArtistAvatar(
                      name: artist.name,
                      size: s(150),
                      imageUrl: coverUrl,
                      headers: headers,
                      fit: BoxFit.contain,
                      paddingFraction: 0,
                    ),
                  ),
                ),
                SizedBox(width: s(24)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MediaHeroTitle(title: artist.name, desktopFontSize: 48, desktopLetterSpacing: 1.6),
                      SizedBox(height: s(6)),
                      DefaultSelectionStyle(
                        selectionColor: accentGold.withValues(alpha: 0.35),
                        child: DismissibleSelectionArea(
                          child: Text(
                            detailsLine,
                            style: GoogleFonts.rajdhani(color: Colors.white54, fontSize: s(12), letterSpacing: s(1.4)),
                          ),
                        ),
                      ),
                      SizedBox(height: s(12)),
                      MediaHeroSummary(text: summary, fontSize: 13, lineHeight: 1.4, collapsedMaxHeight: 72),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
