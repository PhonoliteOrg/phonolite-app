import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/backdrop_color.dart';
import 'package:phonolite_app/ui/shared/music/formatting/album_labels.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';
import 'package:phonolite_app/ui/shared/music/media_hero_details.dart';
import 'package:phonolite_app/ui/shared/music/media_hero_frame.dart';

class AlbumHero extends StatelessWidget {
  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final Widget? actions;

  const AlbumHero({super.key, required this.album, required this.coverUrl, required this.headers, this.actions});

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final isCompact = isCompactListWidth(context);

    double s(double value) => value * scale;

    final genreLine = genreBulletLine(album.genres);
    final detailsLine = genreLine.isEmpty
        ? albumDetailLabel(album, genreLimit: 0)
        : '${albumDetailLabel(album, genreLimit: 0)} / $genreLine';
    final summary = album.summary?.trim();

    final imagePath = coverUrl.trim();
    final backdrop = imagePath.isEmpty ? bgDark : resolveAlbumBackdropColor(imagePath);

    return MediaHeroFrame(
      backgroundLayers: [
        Positioned.fill(child: Container(color: backdrop.withValues(alpha: 0.75))),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [backdrop.withValues(alpha: 0.35), bgDark.withValues(alpha: 0.85)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: isCompact ? 72 : s(170),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AlbumArt(
                    title: album.title,
                    size: isCompact ? 72 : s(150),
                    imageUrl: coverUrl,
                    headers: headers,
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 12 : s(24)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: MediaHeroTitle(title: album.title)),
                        if (actions != null) ...[SizedBox(width: isCompact ? 8 : s(12)), actions!],
                      ],
                    ),
                    SizedBox(height: isCompact ? 4 : s(6)),
                    Text(
                      album.artist,
                      maxLines: isCompact ? 1 : null,
                      overflow: isCompact ? TextOverflow.ellipsis : null,
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: isCompact ? 12 : s(14)),
                    ),
                    SizedBox(height: isCompact ? 4 : s(6)),
                    Text(
                      isCompact ? albumDetailLabel(album, genreLimit: 0) : detailsLine,
                      style: GoogleFonts.rajdhani(
                        color: Colors.white54,
                        fontSize: isCompact ? 11 : s(12),
                        letterSpacing: isCompact ? 0.3 : s(1.4),
                      ),
                    ),
                    if (!isCompact && summary != null && summary.isNotEmpty) ...[
                      SizedBox(height: s(10)),
                      MediaHeroSummary(text: summary),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isCompact && (genreLine.isNotEmpty || (summary != null && summary.isNotEmpty)))
            MediaHeroDetails(
              key: ValueKey('album-details-${album.id}'),
              label: 'Album details',
              genres: genreLine,
              summary: summary,
            ),
        ],
      ),
    );
  }
}
