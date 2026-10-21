import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_scrubber.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class PlaybackProgressBar extends PlaybackScrubber {
  const PlaybackProgressBar({
    super.key,
    required super.sliderTheme,
    required super.maxSeconds,
    required super.position,
    required super.duration,
    required super.animate,
    required super.bufferedPositionSeconds,
    required super.onSeek,
    required super.onSeekPreview,
    required super.enabled,
  });

  @override
  State<PlaybackProgressBar> createState() => PlaybackProgressBarState();
}

class PlaybackProgressBarState extends PlaybackScrubberState<PlaybackProgressBar> {
  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final progressTheme = widget.sliderTheme.copyWith(
      trackHeight: s(6),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(7)),
      thumbColor: Colors.white,
      overlayShape: RoundSliderOverlayShape(overlayRadius: s(18)),
      inactiveTrackColor: Colors.white.withByteOpacity(0.1),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withByteOpacity(0.35),
    );

    final usesTouchTargets = ObsidianModalScope.usesTouchTargets(context);

    final slider = SizedBox(
      height: usesTouchTargets ? 48 : s(36),
      child: SliderTheme(
        data: progressTheme,
        child: Slider(
          value: positionSeconds,
          max: widget.maxSeconds,
          secondaryTrackValue: bufferedPositionSeconds,
          onChangeStart: widget.enabled ? beginDrag : null,
          onChanged: widget.enabled ? updateDrag : null,
          onChangeEnd: widget.enabled ? endDrag : null,
        ),
      ),
    );

    Widget timeLabel(Duration time) => Text(
      playbackFormatTime(time),
      textAlign: TextAlign.center,
      style: GoogleFonts.rajdhani(
        fontSize: s(13),
        // Keep the footer height stable before and after font loading.
        height: 1.0,
        letterSpacing: s(1.1),
        color: ObsidianPalette.textMuted,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: s(2)),
      child: usesTouchTargets
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                slider,
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: s(18)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [timeLabel(displayPosition), timeLabel(widget.duration)],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(width: s(42), child: timeLabel(displayPosition)),
                SizedBox(width: s(12)),
                Expanded(child: slider),
                SizedBox(width: s(12)),
                SizedBox(width: s(42), child: timeLabel(widget.duration)),
              ],
            ),
    );
  }
}
