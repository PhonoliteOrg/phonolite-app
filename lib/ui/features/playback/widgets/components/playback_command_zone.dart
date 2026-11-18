import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_repeat_label.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_shuffle_labels.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';

class PlaybackCommandZone extends StatelessWidget {
  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  const PlaybackCommandZone({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onStop,
    required this.onShuffle,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    final transportEnabled = PlaybackControlsController.transportControlsEnabled(state);
    final playEnabled = transportEnabled && !state.isLoading;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ObsidianHudIconButton(
              semanticLabel: playbackShuffleButtonLabel(state.shuffleMode),
              icon: PhonoliteIcons.shuffle,
              isActive: state.shuffleMode != ShuffleMode.off,
              toggled: state.shuffleMode != ShuffleMode.off,
              onPressed: onShuffle,
              size: s(24),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              semanticLabel: 'Previous track',
              icon: PhonoliteIcons.skipBack,
              onPressed: transportEnabled ? onPrev : null,
              size: s(26),
            ),
            SizedBox(width: s(8)),
            PlaybackHudPlayButton(
              icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
              semanticLabel: state.isPlaying ? 'Pause' : 'Play',
              onPressed: playEnabled ? onPlayPause : null,
            ),
            SizedBox(width: s(8)),
            ObsidianHudIconButton(
              semanticLabel: 'Stop',
              icon: PhonoliteIcons.square,
              onPressed: transportEnabled ? onStop : null,
              size: s(28),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              semanticLabel: 'Next track',
              icon: PhonoliteIcons.skipForward,
              onPressed: transportEnabled ? onNext : null,
              size: s(26),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              semanticLabel: playbackRepeatButtonLabel(state.repeatMode),
              icon: PhonoliteIcons.repeat,
              isActive: state.repeatMode == PlaybackRepeatMode.one,
              toggled: state.repeatMode == PlaybackRepeatMode.one,
              onPressed: onRepeat,
              size: s(24),
            ),
          ],
        ),
      ],
    );
  }
}
