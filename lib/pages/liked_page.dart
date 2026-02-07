import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_row_tile.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/ui/obsidian_widgets.dart';

class LikedPage extends StatefulWidget {
  const LikedPage({super.key});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (controller.liked.isEmpty) {
      controller.loadLikedTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<Track>>(
      stream: controller.likedStream,
      initialData: controller.liked,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, tracks.length),
              const SizedBox(height: 16),
              Expanded(
                child: tracks.isEmpty
                    ? const EmptyState(
                        title: 'No liked tracks',
                        message: 'Tap the heart icon on any track to like it.',
                      )
                    : StreamBuilder<PlaybackState>(
                        stream: controller.playbackStream,
                        initialData: controller.playbackState,
                        builder: (context, snapshot) {
                          final playback =
                              snapshot.data ?? controller.playbackState;
                          final playingId = playback.track?.id;
                          return ListView.separated(
                            itemCount: tracks.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final track = tracks[index];
                              return TrackRowTile(
                                track: track,
                                index: index + 1,
                                isPlaying:
                                    playback.isPlaying && playingId == track.id,
                                onTap: () => controller.playLikedTrack(track.id),
                                onLike: () => controller.toggleLike(track),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Icon(Icons.favorite_rounded, size: 42),
        const SizedBox(width: 20),
        Expanded(
          child: ObsidianSectionHeader(
            title: 'Liked Songs',
            subtitle: '$count tracks',
          ),
        ),
      ],
    );
  }
}
