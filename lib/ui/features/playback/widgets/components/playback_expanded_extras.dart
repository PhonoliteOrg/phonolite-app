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
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

class PlaybackExpandedExtras extends StatelessWidget {
  final PlaybackState state;
  final VoidCallback onShuffle;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowDevicePicker;
  final ValueChanged<StreamMode> onStreamModeChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const PlaybackExpandedExtras({
    super.key,
    required this.state,
    required this.onShuffle,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onShowDevicePicker,
    required this.onStreamModeChanged,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

    final usesTouchTargets = ObsidianModalScope.usesTouchTargets(context);
    final actionSize = usesTouchTargets ? 24.0 : s(32);
    final trackAvailable = state.track != null;

    final userActionsEnabled = trackAvailable;
    final actions = <Widget>[
      if (usesTouchTargets)
        ObsidianHudIconButton(
          icon: PhonoliteIcons.shuffle,
          isActive: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: actionSize,
        ),
      ObsidianHudIconButton(
        iconWidget: const PlaylistAddIcon(),
        onPressed: userActionsEnabled ? onAddToPlaylist : null,
        size: actionSize,
      ),
      LikeIconButton(
        isLiked: state.track?.liked == true,
        onPressed: userActionsEnabled ? onToggleLike : null,
        size: actionSize,
      ),
      ObsidianHudIconButton(icon: PhonoliteIcons.speaker, onPressed: onShowDevicePicker, size: actionSize),
      if (state.track != null && !state.isLocalPlayback)
        PlaybackQualityBadge(
          label: playbackStreamLabel(state.streamMode),
          onTap: () => playbackShowStreamModal(context, current: state.streamMode, onSelected: onStreamModeChanged),
        ),
    ];

    if (usesTouchTargets) {
      return LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.center,
          spacing: constraints.maxWidth < 340 ? 8 : 16,
          runSpacing: 12,
          children: actions,
        ),
      );
    }

    final volumeTheme = SliderTheme.of(context).copyWith(
      trackHeight: s(7),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: s(10)),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      activeTrackColor: Colors.white.withValues(alpha: 0.6),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: s(48),
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[if (i > 0) SizedBox(width: s(14)), actions[i]],
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: s(14)),
        Row(
          children: [
            PlaybackVolumeButton(muted: state.volume == 0.0, onPressed: onToggleMute, size: s(28)),
            SizedBox(width: s(8)),
            Expanded(
              child: SliderTheme(
                data: volumeTheme,
                child: Slider(value: state.volume, onChanged: onVolumeChanged),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
