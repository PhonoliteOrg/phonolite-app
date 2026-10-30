import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_scrubber.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_volume_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_slider_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class PlaybackCompactFooterRow extends PlaybackScrubber {
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const PlaybackCompactFooterRow({
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
    required this.volume,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  State<PlaybackCompactFooterRow> createState() => PlaybackCompactFooterRowState();
}

class PlaybackCompactFooterRowState extends PlaybackScrubberState<PlaybackCompactFooterRow> {
  @override
  bool get respectsTickerMode => true;

  @override
  String? get tickTimelineLabel => 'nowPlaying.progress.tick';

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final progressTheme = widget.sliderTheme.copyWith(
      trackHeight: s(5),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(6)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withByteOpacity(0.1),
      activeTrackColor: ObsidianPalette.gold,
      secondaryActiveTrackColor: ObsidianPalette.gold.withByteOpacity(0.35),
    );

    final volumeTheme = widget.sliderTheme.copyWith(
      trackHeight: s(4),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(5)),
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withByteOpacity(0.1),
      activeTrackColor: Colors.white.withByteOpacity(0.6),
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: s(28),
                child: SliderTheme(
                  data: progressTheme,
                  child: ObsidianSliderScope(
                    child: Slider(
                      value: positionSeconds,
                      max: widget.maxSeconds,
                      secondaryTrackValue: bufferedPositionSeconds,
                      onChangeStart: widget.enabled ? beginDrag : null,
                      onChanged: widget.enabled ? updateDrag : null,
                      onChangeEnd: widget.enabled ? endDrag : null,
                    ),
                  ),
                ),
              ),
              SizedBox(height: s(2)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    playbackFormatTime(displayPosition),
                    style: GoogleFonts.rajdhani(
                      fontSize: s(12),
                      letterSpacing: s(0.8),
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                  Text(
                    playbackFormatTime(widget.duration),
                    style: GoogleFonts.rajdhani(
                      fontSize: s(12),
                      letterSpacing: s(0.8),
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: s(10)),
        SizedBox(
          width: s(110),
          child: Row(
            children: [
              PlaybackVolumeButton(muted: widget.volume == 0.0, onPressed: widget.onToggleMute, size: s(18)),
              SizedBox(width: s(6)),
              Expanded(
                child: SliderTheme(
                  data: volumeTheme,
                  child: ObsidianSliderScope(
                    child: Slider(value: widget.volume, onChanged: widget.onVolumeChanged),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
