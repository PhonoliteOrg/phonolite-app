import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_source_tags.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/marquee_text.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';

class NowPlayingMiniBar extends StatelessWidget {
  static const double _height = 72;

  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onExpand;
  final VoidCallback? onOpenAlbum;

  const NowPlayingMiniBar({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onNext,
    required this.onExpand,
    this.onOpenAlbum,
  });

  static double heightForWidth(double width) => _height;

  String _miniSubtitle(Track track) {
    final artist = track.artist.trim();
    final album = track.album.trim();

    if (artist.isEmpty && album.isEmpty) {
      return '';
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

    final scale = ObsidianScale.of(context);
    final track = state.track;
    final transportEnabled = PlaybackControlsController.transportControlsEnabled(state);
    final playEnabled = transportEnabled && !state.isLoading;
    final subtitle = track == null ? 'IDLE' : _miniSubtitle(track);
    final inlineTags = playbackBuildInlineTags(state);
    final tags = inlineTags.isEmpty && track == null ? const [PlaybackTechTag(label: 'IDLE')] : inlineTags;

    final albumId = track?.albumId?.trim();
    final localImageUrl = track?.albumArtPath?.trim();
    final hasLocalImage = localImageUrl != null && localImageUrl.isNotEmpty;
    final String? imageUrl;

    if (hasLocalImage) {
      imageUrl = localImageUrl;
    } else {
      imageUrl = albumId == null || albumId.isEmpty || state.isLocalPlayback
          ? null
          : AppScope.of(context).catalog.buildAlbumCoverUrl(albumId);
    }

    final headers = hasLocalImage ? const <String, String>{} : authHeaders(AppScope.of(context));

    final artSize = s(54);
    final playPadding = s(6);
    final playVisualSize = math.min(42.0, _height - playPadding * 2);
    final playSize = playVisualSize / scale;

    return Padding(
      padding: EdgeInsets.fromLTRB(s(12), 0, s(12), s(12)),
      child: ObsidianGlassSurface(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: withButtonHaptic(onExpand),
            child: Container(
              height: _height,
              padding: EdgeInsets.symmetric(horizontal: s(14)),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: withButtonHaptic(track != null && state.hasPlaylistSource ? onOpenAlbum : null),
                    behavior: HitTestBehavior.opaque,
                    child: ClipRect(
                      child: Container(
                        width: artSize,
                        height: artSize,
                        color: ObsidianPalette.obsidianGlass.withByteOpacity(0.6),
                        child: track == null
                            ? Icon(PhonoliteIcons.music, color: ObsidianPalette.textMuted, size: artSize * 0.5)
                            : AlbumArt(title: track.album, size: artSize, imageUrl: imageUrl, headers: headers),
                      ),
                    ),
                  ),
                  SizedBox(width: s(12)),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarqueeText(
                          text: track?.title ?? 'NO TRACK PLAYING',
                          style: GoogleFonts.rajdhani(
                            fontSize: s(16),
                            fontWeight: FontWeight.w700,
                            letterSpacing: s(0.8),
                          ),
                          velocity: s(26),
                          gap: s(20),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          SizedBox(height: s(2)),
                          MarqueeText(
                            text: subtitle,
                            style: GoogleFonts.poppins(fontSize: s(12), color: ObsidianPalette.textMuted),
                            velocity: s(26 * playbackSubtitleMarqueeSpeedFactor),
                            gap: s(18),
                          ),
                        ],
                        if (tags.isNotEmpty) ...[SizedBox(height: s(4)), playbackTechTagRow(context, tags)],
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Next song',
                    child: ObsidianHudIconButton(
                      icon: PhonoliteIcons.skipForward,
                      onPressed: transportEnabled ? onNext : null,
                      size: s(28),
                    ),
                  ),
                  SizedBox(width: s(8)),
                  GestureDetector(
                    onTap: withButtonHaptic(playEnabled ? onPlayPause : null),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.all(playPadding),
                      child: PlaybackHudPlayButton(
                        icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                        onPressed: playEnabled ? onPlayPause : null,
                        size: playSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
