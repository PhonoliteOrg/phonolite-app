import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../ui/backdrop_color.dart';
import 'album_art.dart';

class AlbumHero extends StatefulWidget {
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
  State<AlbumHero> createState() => AlbumHeroState();
}

class AlbumHeroState extends State<AlbumHero> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final yearLabel = album.year == null ? 'YEAR UNKNOWN' : album.year.toString();
    final genresLine =
        album.genres.isEmpty ? null : album.genres.join(' • ').toUpperCase();
    final summary = album.summary?.trim();
    final provider = NetworkImage(widget.coverUrl, headers: widget.headers);
    final showToggle = summary != null && summary.length > 140;

    return FutureBuilder<Color>(
      future: resolveAlbumBackdropColor(provider, widget.coverUrl),
      builder: (context, snapshot) {
        final backdrop = snapshot.data ?? bgDark;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(color: backdrop.withOpacity(0.75)),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      backdrop.withOpacity(0.35),
                      bgDark.withOpacity(0.85),
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
              child: Container(
                width: 2,
                color: accentGold,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 170,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AlbumArt(
                        title: album.title,
                        size: 150,
                        imageUrl: widget.coverUrl,
                        headers: widget.headers,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
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
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          album.artist,
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          yearLabel,
                          style: GoogleFonts.rajdhani(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (genresLine != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            genresLine,
                            style: GoogleFonts.rajdhani(
                              color: Colors.white38,
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                        if (summary != null && summary.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRect(
                            child: ConstrainedBox(
                              constraints: _expanded
                                  ? const BoxConstraints()
                                  : const BoxConstraints(maxHeight: 60),
                              child: Text(
                                summary,
                                maxLines: _expanded ? null : 3,
                                overflow: _expanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                          if (showToggle)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _expanded = !_expanded),
                              style: TextButton.styleFrom(
                                foregroundColor: accentGold,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 4,
                                ),
                              ),
                              child: Text(_expanded ? 'Collapse' : 'Read more'),
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
}
