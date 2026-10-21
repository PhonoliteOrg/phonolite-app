import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_layout.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_play_button.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_quality_badge.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

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
    double s(double value) => playbackScaled(context, value);

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
              icon: PhonoliteIcons.shuffle,
              isActive: state.shuffleMode != ShuffleMode.off,
              onPressed: onShuffle,
              size: s(24),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              icon: PhonoliteIcons.skipBack,
              onPressed: transportEnabled ? onPrev : null,
              size: s(26),
            ),
            SizedBox(width: s(8)),
            PlaybackHudPlayButton(
              icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
              onPressed: playEnabled ? onPlayPause : null,
            ),
            SizedBox(width: s(8)),
            ObsidianHudIconButton(
              icon: PhonoliteIcons.square,
              onPressed: transportEnabled ? onStop : null,
              size: s(28),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              icon: PhonoliteIcons.skipForward,
              onPressed: transportEnabled ? onNext : null,
              size: s(26),
            ),
            SizedBox(width: s(6)),
            ObsidianHudIconButton(
              icon: PhonoliteIcons.repeat,
              isActive: state.repeatMode == RepeatMode.one,
              onPressed: onRepeat,
              size: s(24),
            ),
          ],
        ),
      ],
    );
  }
}

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
    double s(double value) => playbackScaled(context, value);

    final transportEnabled = PlaybackControlsController.transportControlsEnabled(state);
    final playEnabled = transportEnabled && !state.isLoading;

    if (ObsidianModalScope.usesTouchTargets(context)) {
      final previous = ObsidianHudIconButton(
        icon: PhonoliteIcons.skipBack,
        size: 24,
        onPressed: transportEnabled ? onPrev : null,
      );
      final play = PlaybackHudPlayButton(
        icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
        size: 56,
        onPressed: playEnabled ? onPlayPause : null,
      );
      final next = ObsidianHudIconButton(
        icon: PhonoliteIcons.skipForward,
        size: 24,
        onPressed: transportEnabled ? onNext : null,
      );
      final stop = ObsidianHudIconButton(
        icon: PhonoliteIcons.square,
        size: 22,
        onPressed: transportEnabled ? onStop : null,
      );
      final repeat = ObsidianHudIconButton(
        icon: PhonoliteIcons.repeat,
        size: 22,
        isActive: state.repeatMode == RepeatMode.one,
        onPressed: onRepeat,
      );

      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [previous, repeat, play, stop, next]);
    }

    final leftRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          icon: PhonoliteIcons.shuffle,
          isActive: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: s(32),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(icon: PhonoliteIcons.skipBack, onPressed: transportEnabled ? onPrev : null, size: s(38)),
      ],
    );

    final rightRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianHudIconButton(
          icon: PhonoliteIcons.skipForward,
          onPressed: transportEnabled ? onNext : null,
          size: s(38),
        ),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(icon: PhonoliteIcons.square, onPressed: transportEnabled ? onStop : null, size: s(38)),
        SizedBox(width: s(18)),
        ObsidianHudIconButton(
          icon: PhonoliteIcons.repeat,
          isActive: state.repeatMode == RepeatMode.one,
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

class PlaybackCompactControls extends StatelessWidget {
  final PlaybackState state;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onToggleLike;
  final VoidCallback onShowDevicePicker;
  final VoidCallback onShowStreamMode;

  const PlaybackCompactControls({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onRepeat,
    required this.onAddToPlaylist,
    required this.onToggleLike,
    required this.onShowDevicePicker,
    required this.onShowStreamMode,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => playbackScaled(context, value);

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
        ObsidianHudIconButton(
          icon: PhonoliteIcons.shuffle,
          isActive: state.shuffleMode != ShuffleMode.off,
          onPressed: onShuffle,
          size: s(22),
        ),
        ObsidianHudIconButton(icon: PhonoliteIcons.skipBack, onPressed: transportEnabled ? onPrev : null, size: s(24)),
        PlaybackHudPlayButton(
          icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: playEnabled ? onPlayPause : null,
          size: playSize,
        ),
        ObsidianHudIconButton(
          icon: PhonoliteIcons.skipForward,
          onPressed: transportEnabled ? onNext : null,
          size: s(24),
        ),
        ObsidianHudIconButton(
          icon: PhonoliteIcons.repeat,
          isActive: state.repeatMode == RepeatMode.one,
          onPressed: onRepeat,
          size: s(22),
        ),
        ObsidianHudIconButton(
          iconWidget: const PlaylistAddIcon(),
          onPressed: userActionsEnabled ? onAddToPlaylist : null,
          size: s(22),
        ),
        LikeIconButton(
          isLiked: state.track?.liked == true,
          onPressed: userActionsEnabled ? onToggleLike : null,
          size: s(22),
        ),
        ObsidianHudIconButton(icon: PhonoliteIcons.speaker, onPressed: onShowDevicePicker, size: s(22)),
        if (state.track != null && !state.isLocalPlayback)
          PlaybackQualityBadge(label: playbackStreamLabel(state.streamMode), onTap: onShowStreamMode),
      ],
    );
  }
}
