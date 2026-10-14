import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/artwork_errors.dart';
import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/compact_hero_details.dart';
import '../ui/dismissible_selection_area.dart';
import '../ui/expandable_summary_text.dart';
import '../ui/responsive_breakpoints.dart';
import 'album_labels.dart';
import 'artist_avatar.dart';
import 'genre_text.dart';

class ArtistHero extends StatelessWidget {
  const ArtistHero({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.bannerUrl,
    required this.headers,
  });

  final Artist artist;
  final String? coverUrl;
  final String? bannerUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    final isCompact = isCompactListWidth(context);
    double s(double value) => value * scale;
    final bannerHeight = isCompact ? 140.0 : s(240);
    final bannerPath = bannerUrl?.trim();
    Widget onBannerError(
      BuildContext context,
      Object error,
      StackTrace? stack,
    ) {
      ArtworkErrors.instance.report(bannerPath!, error);
      return const SizedBox.shrink();
    }

    final summary = artist.summary?.trim().isNotEmpty == true
        ? artist.summary!
        : 'Bio unavailable. Curate this artist profile with metadata or notes.';
    final genreLine = genreBulletLine(artist.genres);
    final detailsLine = genreLine.isEmpty
        ? artistDetailLabel(artist, genreLimit: 0)
        : '${artistDetailLabel(artist, genreLimit: 0)} / $genreLine';

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: isCompact ? 0 : s(220)),
      child: Stack(
        children: [
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
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.7, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: _isRemoteImage(bannerPath)
                        ? Image.network(
                            bannerPath,
                            headers: headers,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: onBannerError,
                          )
                        : Image.file(
                            File(bannerPath),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: onBannerError,
                          ),
                  ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    bgDark.withValues(alpha: 0.0),
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
            child: isCompact
                ? _compactHeader(
                    genreLine: genreLine,
                    summary: artist.summary?.trim(),
                  )
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
                            Text(
                              artist.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.rajdhani(
                                color: Colors.white,
                                fontSize: s(48),
                                fontWeight: FontWeight.w700,
                                letterSpacing: s(1.6),
                                height: 1.05,
                              ),
                            ),
                            SizedBox(height: s(6)),
                            DefaultSelectionStyle(
                              selectionColor: accentGold.withValues(
                                alpha: 0.35,
                              ),
                              child: DismissibleSelectionArea(
                                child: Text(
                                  detailsLine,
                                  style: GoogleFonts.rajdhani(
                                    color: Colors.white54,
                                    fontSize: s(12),
                                    letterSpacing: s(1.4),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: s(12)),
                            ExpandableSummaryText(
                              text: summary,
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: s(13),
                                height: 1.4,
                              ),
                              toggleColor: accentGold,
                              collapsedMaxHeight: s(72),
                              togglePadding: EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: s(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

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
                  Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artistDetailLabel(artist, genreLimit: 0),
                    style: GoogleFonts.rajdhani(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (genreLine.isNotEmpty || hasSummary)
          CompactHeroDetails(
            key: ValueKey('artist-details-${artist.id}'),
            label: 'About artist',
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
                    if (genreLine.isNotEmpty && hasSummary)
                      const SizedBox(height: 8),
                    if (hasSummary)
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
    );
  }

  bool _isRemoteImage(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}
