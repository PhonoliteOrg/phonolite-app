import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../ui/blur.dart';
import '../ui/chamfered.dart';
import 'artist_avatar.dart';
import 'card_image_frame.dart';

class ArtistCard extends StatefulWidget {
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
  State<ArtistCard> createState() => ArtistCardState();
}

class ArtistCardState extends State<ArtistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = ClipPath(
      clipper: DiagonalChamferClipper(cut: 20),
      child: maybeBlur(
        sigma: cardBackdropBlurSigma,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: cardGlowAnimMs),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(cardTopOpacity),
                Colors.white.withOpacity(cardBottomOpacity),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: cardOverlayAnimMs),
                  opacity: _hovered ? 1 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(cardHoverOverlayTopOpacity),
                          Colors.white
                              .withOpacity(cardHoverOverlayBottomOpacity),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CardImageFrame(
                        hovered: _hovered,
                        child: ArtistAvatar(
                          name: widget.artist.name,
                          size: 120,
                          imageUrl: widget.coverUrl,
                          headers: widget.headers,
                          fit: BoxFit.contain,
                          paddingFraction: 0,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.artist.albumCount} ALBUMS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final card = content;

    final useHover = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    final interactive = useHover
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(onTap: widget.onTap, child: card),
          )
        : InkWell(
            onTap: widget.onTap,
            splashColor: accentGold.withOpacity(0.2),
            child: card,
          );

    return interactive;
  }
}
