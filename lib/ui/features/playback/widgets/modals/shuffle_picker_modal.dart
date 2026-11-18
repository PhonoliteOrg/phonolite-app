import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/playback_controls_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_shuffle_labels.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/shuffle_mode_changed.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/playback_picker_dialog.dart';
import 'package:phonolite_app/ui/features/playback/widgets/modals/playback_picker_option.dart';
import 'package:phonolite_app/ui/shared/music/local_server_toggle.dart';

Future<void> playbackShowShuffleModal(BuildContext context, {required ShuffleModeChanged onSelected}) async {
  final controller = AppScope.of(context);
  var scope = controller.playbackState.shuffleScope;

  PlaybackControlsController.warmShuffleLikedState(
    controller,
    serverScope: scope == ActionScope.server,
    serverAvailable: controller.authState.isAuthorized,
  );

  if (!context.mounted) {
    return;
  }

  final result = await showPlaybackPicker<({ShuffleMode mode, ActionScope scope})>(
    context,
    title: 'Shuffle',
    scrollable: true,
    contentBuilder: (_) {
      const items = [
        ShuffleMode.off,
        ShuffleMode.all,
        ShuffleMode.artist,
        ShuffleMode.album,
        ShuffleMode.currentPlaylist,
        ShuffleMode.custom,
        ShuffleMode.liked,
      ];

      return StatefulBuilder(
        builder: (context, setModalState) {
          void selectScope(ActionScope value) {
            if (value == scope) {
              return;
            }

            onSelected(controller.playbackState.shuffleModeFor(value), scope: value);
            setModalState(() => scope = value);

            PlaybackControlsController.warmShuffleLikedState(
              controller,
              serverScope: value == ActionScope.server,
              serverAvailable: controller.authState.isAuthorized,
            );
          }

          final playback = controller.playbackState;
          final serverScope = scope == ActionScope.server;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: LocalServerToggle(value: scope, onChanged: selectScope),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Track>>(
                key: ValueKey(scope),
                stream: serverScope ? controller.likedStream : controller.localLikedStream,
                initialData: serverScope ? controller.liked : controller.localLiked,
                builder: (context, likedSnapshot) {
                  final likedEnabled = (likedSnapshot.data ?? const <Track>[]).isNotEmpty;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: items.map((mode) {
                      final selected = mode == playback.shuffleModeFor(scope);
                      final enabled = PlaybackControlsController.shuffleEnabled(
                        controller,
                        playback,
                        scope,
                        mode,
                        likedEnabled: likedEnabled,
                      );

                      return PlaybackPickerOption(
                        enabled: enabled,
                        title: playbackShuffleLabel(mode),
                        value: (mode: mode, scope: scope),
                        isSelected: selected,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null &&
      (result.mode != controller.playbackState.shuffleMode || result.scope != controller.playbackState.shuffleScope)) {
    onSelected(result.mode, scope: result.scope);
  }
}
