import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import '../ui/backdrop_color.dart';
import '../ui/expandable_summary_text.dart';
import 'album_art.dart';
import 'album_labels.dart';
import 'genre_text.dart';

class AlbumHero extends StatelessWidget {
  const AlbumHero({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
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
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: s(2), color: accentGold),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(s(24), s(20), s(20), s(20)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: s(170),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AlbumArt(
                        title: album.title,
                        size: s(150),
                        imageUrl: coverUrl,
                        headers: headers,
                      ),
                    ),
                  ),
                  SizedBox(width: s(24)),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.rajdhani(
                            color: Colors.white,
                            fontSize: s(42),
                            fontWeight: FontWeight.w700,
                            letterSpacing: s(1.4),
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: s(6)),
                        Text(
                          album.artist,
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: s(14),
                          ),
                        ),
                        SizedBox(height: s(6)),
                        Text(
                          detailsLine,
                          style: GoogleFonts.rajdhani(
                            color: Colors.white54,
                            fontSize: s(12),
                            letterSpacing: s(1.4),
                          ),
                        ),
                        if (summary != null && summary.isNotEmpty) ...[
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
