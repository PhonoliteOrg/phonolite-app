import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/album_hero.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/navigation/command_link_button.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.artistName,
  });

  final Album album;
  final String artistName;

  @override
  State<AlbumDetailScreen> createState() => AlbumDetailScreenState();
}

class AlbumDetailScreenState extends State<AlbumDetailScreen> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final controller = AppScope.of(context);
    controller.loadTracks(widget.album.id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = controller.connection.buildAlbumCoverUrl(widget.album.id);

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: controller.tracksLoadingStream,
          initialData: controller.tracksLoading,
          builder: (context, loadingSnapshot) {
            final isLoading = loadingSnapshot.data ?? false;
            return StreamBuilder<List<Track>>(
              stream: controller.tracksStream,
              initialData: controller.tracks,
              builder: (context, snapshot) {
                final tracks = snapshot.data ?? [];
                return StreamBuilder<PlaybackState>(
                  stream: controller.playbackStream,
                  initialData: controller.playbackState,
                  builder: (context, playbackSnapshot) {
                    final playback =
                        playbackSnapshot.data ?? controller.playbackState;
                    final playingId = playback.track?.id;
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          sliver: SliverToBoxAdapter(
                            child: CommandLinkButton(
                              label: 'Back to artist',
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          sliver: SliverToBoxAdapter(
                            child: AlbumHero(
                              album: widget.album,
                              coverUrl: coverUrl,
                              headers: authHeadersMap,
                            ),
                          ),
                        ),
                        if (isLoading && tracks.isEmpty)
                          loadingSliver()
                        else if (tracks.isEmpty)
                          const SliverPadding(
                            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                            sliver: SliverToBoxAdapter(
                              child: EmptyState(
                                title: 'No tracks',
                                message: 'Pick another album to see tracks.',
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            sliver: TrackSliverList(
                              tracks: tracks,
                              isPlayingTrack: (track) =>
                                  playback.isPlaying && playingId == track.id,
                              onTrackTap: (track) => controller.queueAlbum(
                                widget.album.id,
                                startTrackId: track.id,
                              ),
                              onTrackAddToPlaylist: (track) =>
                                  showAddToPlaylistModalForTrack(
                                    context,
                                    track,
                                  ),
                              onTrackLike: controller.toggleLike,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
