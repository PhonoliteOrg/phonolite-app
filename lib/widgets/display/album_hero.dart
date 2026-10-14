import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/backdrop_color.dart';
import '../ui/compact_hero_details.dart';
import '../ui/dismissible_selection_area.dart';
import '../ui/expandable_summary_text.dart';
import '../ui/responsive_breakpoints.dart';
import 'album_art.dart';
import 'album_labels.dart';
import 'genre_text.dart';

class AlbumHero extends StatelessWidget {
  const AlbumHero({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    this.actions,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final Widget? actions;

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
    final provider = imagePath.isEmpty
        ? null
        : _isRemoteImage(imagePath)
        ? NetworkImage(imagePath, headers: headers) as ImageProvider
        : FileImage(File(imagePath));

    return FutureBuilder<Color>(
      future: provider == null
          ? Future<Color>.value(bgDark)
          : resolveAlbumBackdropColor(provider, imagePath),
      builder: (context, snapshot) {
        final backdrop = snapshot.data ?? bgDark;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(color: backdrop.withValues(alpha: 0.75)),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      backdrop.withValues(alpha: 0.35),
                      bgDark.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: isCompact
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : EdgeInsets.fromLTRB(s(24), s(20), s(20), s(20)),
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
                                Expanded(
                                  child: Text(
                                    album.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.rajdhani(
                                      color: Colors.white,
                                      fontSize: isCompact ? 24 : s(42),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: isCompact ? 0.3 : s(1.4),
                                      height: 1.05,
                                    ),
                                  ),
                                ),
                                if (actions != null) ...[
                                  SizedBox(width: isCompact ? 8 : s(12)),
                                  actions!,
                                ],
                              ],
                            ),
                            SizedBox(height: isCompact ? 4 : s(6)),
                            Text(
                              album.artist,
                              maxLines: isCompact ? 1 : null,
                              overflow: isCompact
                                  ? TextOverflow.ellipsis
                                  : null,
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: isCompact ? 12 : s(14),
                              ),
                            ),
                            SizedBox(height: isCompact ? 4 : s(6)),
                            Text(
                              isCompact
                                  ? albumDetailLabel(album, genreLimit: 0)
                                  : detailsLine,
                              style: GoogleFonts.rajdhani(
                                color: Colors.white54,
                                fontSize: isCompact ? 11 : s(12),
                                letterSpacing: isCompact ? 0.3 : s(1.4),
                              ),
                            ),
                            if (!isCompact &&
                                summary != null &&
                                summary.isNotEmpty) ...[
                              SizedBox(height: s(10)),
                              ExpandableSummaryText(
                                text: summary,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: s(12),
                                  height: 1.35,
                                ),
                                toggleColor: accentGold,
                                collapsedMaxHeight: s(60),
                                togglePadding: EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: s(4),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isCompact &&
                      (genreLine.isNotEmpty ||
                          (summary != null && summary.isNotEmpty)))
                    CompactHeroDetails(
                      key: ValueKey('album-details-${album.id}'),
                      label: 'Album details',
                      child: DefaultSelectionStyle(
                        selectionColor: accentGold.withValues(alpha: 0.35),
                        child: DismissibleSelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (genreLine.isNotEmpty)
                                Text(
                                  genreLine,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              if (genreLine.isNotEmpty &&
                                  summary != null &&
                                  summary.isNotEmpty)
                                const SizedBox(height: 8),
                              if (summary != null && summary.isNotEmpty)
                                Text(
                                  summary,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isRemoteImage(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}
