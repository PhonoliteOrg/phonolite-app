import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_source_tags.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/marquee_text.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';

class PlaybackIntelZone extends StatelessWidget {
  final Track? track;
  final bool isLoading;
  final VoidCallback? onTap;
  final List<Widget> techTags;
  final List<Widget> sourceTags;
  final bool wrapTags;

  const PlaybackIntelZone({
    super.key,
    required this.track,
    required this.isLoading,
    required this.techTags,
    required this.sourceTags,
    this.wrapTags = true,
    this.onTap,
  });

  String _subtitle(Track? track) {
    if (track == null) {
      return 'IDLE';
    }

    final artist = track.artist.trim();
    final album = track.album.trim();

    if (artist.isEmpty && album.isEmpty) {
      return 'IDLE';
    }

    if (artist.isEmpty) {
      return album;
    }

    if (album.isEmpty) {
      return artist;
    }

    return '$artist - $album';
  }

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final tags = techTags.isEmpty && track == null ? const [PlaybackTechTag(label: 'IDLE')] : techTags;
    final enabled = onTap != null && track != null;
    final subtitle = _subtitle(track);
    final displayTags = sourceTags.isEmpty ? tags : [...sourceTags, ...tags];

    final content = Row(
      children: [
        PlaybackAlbumArtThumb(track: track, isLoading: isLoading),
        SizedBox(width: s(12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(
                key: ValueKey('title-${track?.id ?? 'idle'}'),
                text: track?.title ?? 'NO TRACK PLAYING',
                style: GoogleFonts.rajdhani(fontSize: s(17), fontWeight: FontWeight.w700, letterSpacing: s(1.0)),
                velocity: s(32),
                gap: s(24),
              ),
              SizedBox(height: s(1)),
              MarqueeText(
                key: ValueKey('subtitle-${track?.id ?? 'idle'}'),
                text: subtitle,
                style: GoogleFonts.poppins(fontSize: s(11), color: ObsidianPalette.textMuted),
                velocity: s(32 * playbackSubtitleMarqueeSpeedFactor),
                gap: s(24),
              ),
              SizedBox(height: s(3)),
              playbackTechTagRow(context, displayTags, wrap: wrapTags),
            ],
          ),
        ),
      ],
    );

    final paddedContent = Padding(
      padding: EdgeInsets.symmetric(vertical: s(6), horizontal: s(4)),
      child: content,
    );

    if (!enabled) {
      return paddedContent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: withButtonHaptic(onTap),
          borderRadius: BorderRadius.circular(s(12)),
          child: paddedContent,
        ),
      ),
    );
  }
}

class PlaybackAlbumArtThumb extends StatelessWidget {
  final Track? track;
  final bool isLoading;

  const PlaybackAlbumArtThumb({super.key, required this.track, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final albumId = track?.albumId?.trim();
    final localImageUrl = track?.albumArtPath?.trim();
    final hasLocalImage = localImageUrl != null && localImageUrl.isNotEmpty;
    final String? imageUrl;

    if (hasLocalImage) {
      imageUrl = localImageUrl;
    } else {
      imageUrl = albumId == null || albumId.isEmpty ? null : AppScope.of(context).catalog.buildAlbumCoverUrl(albumId);
    }

    final placeholder = Container(
      color: ObsidianPalette.obsidianGlass.withByteOpacity(0.6),
      alignment: Alignment.center,
      child: Text(
        (track?.title.isNotEmpty == true) ? track!.title.substring(0, 1).toUpperCase() : '?',
        style: GoogleFonts.rajdhani(fontSize: s(20), fontWeight: FontWeight.w700),
      ),
    );

    final image = AlbumArt(
      title: track?.album ?? '',
      size: s(64),
      imageUrl: imageUrl,
      headers: hasLocalImage || imageUrl == null ? const <String, String>{} : authHeaders(AppScope.of(context)),
      placeholder: placeholder,
    );

    return ClipRect(
      child: SizedBox(
        width: s(64),
        height: s(64),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (isLoading)
              ColoredBox(
                color: Colors.black.withByteOpacity(0.34),
                child: Center(
                  child: SizedBox(
                    width: s(18),
                    height: s(18),
                    child: CircularProgressIndicator(
                      strokeWidth: s(2.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(ObsidianPalette.gold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
