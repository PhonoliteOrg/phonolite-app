import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_repeat_label.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_shuffle_labels.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';

class PlaybackExpandedControls extends StatelessWidget {
  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  const PlaybackExpandedControls({
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

    if (ObsidianModalScope.usesTouchTargets(context)) {
      final previous = ObsidianHudIconButton(
        semanticLabel: 'Previous track',
        icon: PhonoliteIcons.skipBack,
        size: 24,
        onPressed: transportEnabled ? onPrev : null,
      );
      final play = PlaybackHudPlayButton(
        icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
        semanticLabel: state.isPlaying ? 'Pause' : 'Play',
        size: 56,
        onPressed: playEnabled ? onPlayPause : null,
      );
      final next = ObsidianHudIconButton(
        semanticLabel: 'Next track',
        icon: PhonoliteIcons.skipForward,
        size: 24,
        onPressed: transportEnabled ? onNext : null,
      );
      final stop = ObsidianHudIconButton(
        semanticLabel: 'Stop',
        icon: PhonoliteIcons.square,
        size: 22,
        onPressed: transportEnabled ? onStop : null,
      );
      final repeat = ObsidianHudIconButton(
        semanticLabel: playbackRepeatButtonLabel(state.repeatMode),
        icon: PhonoliteIcons.repeat,
        size: 22,
        isActive: state.repeatMode == PlaybackRepeatMode.one,
        toggled: state.repeatMode == PlaybackRepeatMode.one,
        onPressed: onRepeat,
      );

      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [previous, repeat, play, stop, next]);
    }

    final leftRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          semanticLabel: playbackShuffleButtonLabel(state.shuffleMode),
          icon: PhonoliteIcons.shuffle,
          isActive: state.shuffleMode != ShuffleMode.off,
          toggled: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: s(32),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          semanticLabel: 'Previous track',
          icon: PhonoliteIcons.skipBack,
          onPressed: transportEnabled ? onPrev : null,
          size: s(38),
        ),
      ],
    );

    final rightRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          semanticLabel: 'Next track',
          icon: PhonoliteIcons.skipForward,
          onPressed: transportEnabled ? onNext : null,
          size: s(38),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          semanticLabel: 'Stop',
          icon: PhonoliteIcons.square,
          onPressed: transportEnabled ? onStop : null,
          size: s(38),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          semanticLabel: playbackRepeatButtonLabel(state.repeatMode),
          icon: PhonoliteIcons.repeat,
          isActive: state.repeatMode == PlaybackRepeatMode.one,
          toggled: state.repeatMode == PlaybackRepeatMode.one,
          onPressed: onRepeat,
          size: s(32),
        ),
      ],
    );

    return SizedBox(
      height: s(96),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final rawPlaySize = s(98);
          final playSize = math.min(rawPlaySize, maxWidth);
          final maxGap = ((maxWidth - playSize) / 2).clamp(0.0, double.infinity);
          final gap = math.min(s(12), maxGap);
          final sideWidth = ((maxWidth - playSize - gap * 2) / 2).clamp(0.0, double.infinity);

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: leftRow),
                ),
              ),
              SizedBox(width: gap),
              PlaybackHudPlayButton(
                icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                semanticLabel: state.isPlaying ? 'Pause' : 'Play',
                onPressed: playEnabled ? onPlayPause : null,
                size: playSize,
              ),
              SizedBox(width: gap),
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: rightRow),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
