import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../entities/models.dart';
import '../ui/blur.dart';
import '../ui/chamfered.dart';
import 'album_art.dart';
import 'album_labels.dart';
import 'card_image_frame.dart';

class AlbumCard extends StatefulWidget {
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
  State<AlbumCard> createState() => AlbumCardState();
}

class AlbumCardState extends State<AlbumCard> {
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
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxImageSize =
                          math.min(albumPortraitSize, constraints.maxWidth);
                      final reservedTextHeight = 74.0;
                      final availableForImage =
                          (constraints.maxHeight - reservedTextHeight)
                              .clamp(80.0, albumPortraitSize);
                      final imageSize = math.min(maxImageSize, availableForImage);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CardImageFrame(
                            hovered: _hovered,
                            borderRadius: BorderRadius.zero,
                            child: AlbumArt(
                              title: widget.album.title,
                              size: imageSize,
                              imageUrl: widget.coverUrl,
                              headers: widget.headers,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            albumYearLabel(widget.album),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              color: Colors.white54,
                              fontSize: 11,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const SizedBox.shrink(),
                        ],
                      );
                    },
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
