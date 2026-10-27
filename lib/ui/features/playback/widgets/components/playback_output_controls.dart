import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_quality_badge.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_volume_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/stream_quality_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

class PlaybackOutputZone extends StatelessWidget {
  final PlaybackState state;
  final bool compact;
  final bool allowWrap;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowDevicePicker;

  const PlaybackOutputZone({
    super.key,
    required this.state,
    required this.compact,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onShowDevicePicker,
    this.allowWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final volumeTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(6),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(8)),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withByteOpacity(0.1),
      activeTrackColor: Colors.white.withByteOpacity(0.6),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = compact || (allowWrap && constraints.maxWidth < s(320));
        final controlSpacing = isTight ? s(10) : s(16);
        final userActionsEnabled = state.track != null;

        final controls = <Widget>[
          ObsidianHudIconButton(
            iconWidget: const PlaylistAddIcon(),
            onPressed: userActionsEnabled ? onAddToPlaylist : null,
            size: s(26),
          ),
          LikeIconButton(
            isLiked: state.track?.liked == true,
            onPressed: userActionsEnabled ? onToggleLike : null,
            size: s(26),
          ),
          ObsidianHudIconButton(icon: PhonoliteIcons.speaker, onPressed: onShowDevicePicker, size: s(26)),
          if (state.track != null && !state.isLocalPlayback)
            PlaybackQualityBadge(
              label: playbackStreamLabel(state.streamMode),
              onTap: () => playbackShowStreamModal(context, current: state.streamMode, onSelected: onStreamModeChanged),
            ),
        ];

        final controlsRow = isTight
            ? Wrap(
                alignment: compact ? WrapAlignment.center : WrapAlignment.end,
                spacing: controlSpacing,
                runSpacing: s(6),
                children: controls,
              )
            : Row(
                mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.end,
                children: [
                  controls[0],
                  SizedBox(width: s(14)),
                  controls[1],
                  SizedBox(width: controlSpacing),
                  controls[2],
                  if (state.track != null && !state.isLocalPlayback) ...[SizedBox(width: controlSpacing), controls[3]],
                ],
              );

        final sliderWidth = isTight ? constraints.maxWidth : s(200);
        final sliderRow = Align(
          alignment: compact ? Alignment.center : Alignment.centerRight,
          child: SizedBox(
            width: sliderWidth,
            child: Row(
              children: [
                PlaybackVolumeButton(muted: state.volume == 0.0, onPressed: onToggleMute, size: s(26)),
                SizedBox(width: s(8)),
                Expanded(
                  child: SliderTheme(
                    data: volumeTheme,
                    child: Slider(value: state.volume, onChanged: onVolumeChanged),
                  ),
                ),
              ],
            ),
          ),
        );

        return Row(
          mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.end,
                children: [
                  controlsRow,
                  SizedBox(height: s(8)),
                  sliderRow,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
