import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../layouts/obsidian_scale.dart';
import 'artist_avatar.dart';

class ArtistHero extends StatefulWidget {
  const ArtistHero({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.bannerUrl,
    required this.headers,
  });

  final Artist artist;
  final String coverUrl;
  final String bannerUrl;
  final Map<String, String> headers;

  @override
  State<ArtistHero> createState() => ArtistHeroState();
}

class ArtistHeroState extends State<ArtistHero>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scale = ObsidianScale.of(context);
    double s(double value) => value * scale;
    final artist = widget.artist;
    final bannerUrl = widget.bannerUrl;
    final headers = widget.headers;
    final bannerHeight = s(240);
    final summary = artist.summary?.trim().isNotEmpty == true
        ? artist.summary!
        : 'Bio unavailable. Curate this artist profile with metadata or notes.';
    final genresLine =
        artist.genres.isEmpty ? null : artist.genres.join(' • ').toUpperCase();
    final showToggle = summary.length > 140;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: s(220)),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: bannerHeight,
            child: ShaderMask(
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
              child: Image.network(
                bannerUrl,
                headers: headers,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    bgDark.withOpacity(0.0),
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
              width: s(2),
              color: accentGold,
            ),
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
                    child: ArtistAvatar(
                      name: artist.name,
                      size: s(150),
                      imageUrl: widget.coverUrl,
                      headers: widget.headers,
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
                      if (genresLine != null) ...[
                        SizedBox(height: s(6)),
                        Text(
                          genresLine,
                          style: GoogleFonts.rajdhani(
                            color: Colors.white54,
                            fontSize: s(12),
                            letterSpacing: s(1.4),
                          ),
                        ),
                      ],
                      SizedBox(height: s(12)),
                      ClipRect(
                        child: ConstrainedBox(
                          constraints: _expanded
                              ? const BoxConstraints()
                              : BoxConstraints(maxHeight: s(72)),
                          child: Text(
                            summary,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            maxLines: _expanded ? null : 3,
                            softWrap: true,
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: s(13),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      if (showToggle)
                        TextButton(
                          onPressed: () => setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            foregroundColor: accentGold,
                            padding:
                                EdgeInsets.symmetric(horizontal: 0, vertical: s(4)),
                          ),
                          child: Text(_expanded ? 'Collapse' : 'Read more'),
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
}
