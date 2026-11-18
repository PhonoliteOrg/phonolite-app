import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_queue_source_label.dart';
import 'package:phonolite_app/ui/features/playback/widgets/components/playback_tech_tag.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';

const _queueSourceGreen = Color(0xFF2ED573);
const _playlistSourcePurple = Color(0xFFB388FF);

List<Widget> playbackBuildQueueSourceTags(PlaybackState state) {
  if (state.track == null) {
    return const [];
  }

  if (state.queueSource == PlaybackQueueSource.playlist ||
      (state.queueSource == PlaybackQueueSource.offline && state.localPlaybackSource == LocalPlaybackSource.playlist)) {
    return [
      PlaybackPlaylistSourceTag(
        playlistId: state.queueSourcePlaylistId,
        isLocal: state.queueSource == PlaybackQueueSource.offline,
      ),
    ];
  }

  final label = playbackQueueSourceLabel(state);
  if (label == null) {
    return const [];
  }

  final isLikedSource =
      state.queueSource == PlaybackQueueSource.liked ||
      (state.queueSource == PlaybackQueueSource.offline && state.localPlaybackSource == LocalPlaybackSource.liked);

  return [
    PlaybackTechTag(
      label: label,
      highlight: isLikedSource,
      outlineColor: isLikedSource ? null : _queueSourceGreen.withByteOpacity(0.7),
    ),
  ];
}

class PlaybackPlaylistSourceTag extends StatelessWidget {
  final String? playlistId;
  final bool isLocal;

  const PlaybackPlaylistSourceTag({super.key, required this.playlistId, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final playlists = isLocal ? controller.localPlaylists : controller.playlists;

    return StreamBuilder<List<Playlist>>(
      stream: isLocal ? controller.localPlaylistsStream : controller.playlistsStream,
      initialData: playlists,
      builder: (context, snapshot) {
        var name = 'Playlist';

        for (final playlist in snapshot.data ?? playlists) {
          if (playlist.id == playlistId) {
            name = playlist.name;
            break;
          }
        }

        return PlaybackTechTag(label: name, outlineColor: _playlistSourcePurple.withValues(alpha: 0.7));
      },
    );
  }
}
