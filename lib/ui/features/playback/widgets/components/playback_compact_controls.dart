import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_quality_badge.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_repeat_label.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_shuffle_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_stream_labels.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

class PlaybackCompactControls extends StatelessWidget {
  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onToggleLike;
  final VoidCallback onShowDevicePicker;
  final VoidCallback onShowStreamMode;
  final bool touchTargets;

  const PlaybackCompactControls({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onStop,
    required this.onShuffle,
    required this.onRepeat,
    required this.onAddToPlaylist,
    required this.onToggleLike,
    required this.onShowDevicePicker,
    required this.onShowStreamMode,
    this.touchTargets = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    final scale = ObsidianScale.of(context);
    final playSize = 64 / scale;
    final transportEnabled = PlaybackControlsController.transportControlsEnabled(state);
    final playEnabled = transportEnabled && !state.isLoading;
    final trackAvailable = state.track != null;
    final userActionsEnabled = trackAvailable;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: s(8),
      runSpacing: s(8),
      children: [
        for (final control in <Widget>[
          ObsidianHudIconButton(
            semanticLabel: playbackShuffleButtonLabel(state.shuffleMode),
            icon: PhonoliteIcons.shuffle,
            isActive: state.shuffleMode != ShuffleMode.off,
            toggled: state.shuffleMode != ShuffleMode.off,
            onPressed: onShuffle,
            size: s(22),
          ),
          ObsidianHudIconButton(
            semanticLabel: 'Previous track',
            icon: PhonoliteIcons.skipBack,
            onPressed: transportEnabled ? onPrev : null,
            size: s(24),
          ),
          PlaybackHudPlayButton(
            icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
            semanticLabel: state.isPlaying ? 'Pause' : 'Play',
            onPressed: playEnabled ? onPlayPause : null,
            size: playSize,
          ),
          ObsidianHudIconButton(
            semanticLabel: 'Stop',
            icon: PhonoliteIcons.square,
            onPressed: transportEnabled ? onStop : null,
            size: s(24),
          ),
          ObsidianHudIconButton(
            semanticLabel: 'Next track',
            icon: PhonoliteIcons.skipForward,
            onPressed: transportEnabled ? onNext : null,
            size: s(24),
          ),
          ObsidianHudIconButton(
            semanticLabel: playbackRepeatButtonLabel(state.repeatMode),
            icon: PhonoliteIcons.repeat,
            isActive: state.repeatMode == PlaybackRepeatMode.one,
            toggled: state.repeatMode == PlaybackRepeatMode.one,
            onPressed: onRepeat,
            size: s(22),
          ),
          ObsidianHudIconButton(
            semanticLabel: 'Add to playlist',
            iconWidget: const PlaylistAddIcon(),
            onPressed: userActionsEnabled ? onAddToPlaylist : null,
            size: s(22),
          ),
          LikeIconButton(
            isLiked: state.track?.liked == true,
            onPressed: userActionsEnabled ? onToggleLike : null,
            size: s(22),
          ),
          ObsidianHudIconButton(
            semanticLabel: 'Playback device',
            icon: PhonoliteIcons.speaker,
            onPressed: onShowDevicePicker,
            size: s(22),
          ),
          if (state.track != null && !state.isLocalPlayback)
            PlaybackQualityBadge(label: playbackStreamLabel(state.streamMode), onTap: onShowStreamMode),
        ])
          if (touchTargets)
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48), child: control)
          else
            control,
      ],
    );
  }
}
