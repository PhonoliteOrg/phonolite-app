import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/album_hero.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_row_tile.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
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
  bool _albumHeroReady = false;
  String _albumHeroKey = '';

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

  void _ensureAlbumHeroReady(
    BuildContext context,
    String coverUrl,
    Map<String, String> headers,
  ) {
    if (_albumHeroKey == coverUrl) {
      return;
    }
    _albumHeroKey = coverUrl;
    _albumHeroReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await precacheImages(context, [coverUrl], headers: headers);
      if (!mounted || _albumHeroKey != coverUrl) {
        return;
      }
      setState(() => _albumHeroReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = controller.connection.buildAlbumCoverUrl(widget.album.id);
    _ensureAlbumHeroReady(context, coverUrl, authHeadersMap);

    return Scaffold(
      backgroundColor: bgDark,
      body: Stack(
        children: [
          const SizedBox.shrink(),
          SafeArea(
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
                    final ready = _albumHeroReady && !isLoading;
                    if (!ready) {
                      return fullPageSpinner();
                    }
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
                              padding:
                                  const EdgeInsets.fromLTRB(20, 16, 20, 16),
                              sliver: SliverToBoxAdapter(
                                child: CommandLinkButton(
                                  label: 'Back to artist',
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              sliver: SliverToBoxAdapter(
                                child: AlbumHero(
                                  album: widget.album,
                                  coverUrl: coverUrl,
                                  headers: authHeadersMap,
                                ),
                              ),
                            ),
                            if (tracks.isEmpty)
                              const SliverPadding(
                                padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                                sliver: SliverToBoxAdapter(
                                  child: EmptyState(
                                    title: 'No tracks',
                                    message:
                                        'Pick another album to see tracks.',
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (index.isOdd) {
                                        return const Divider(height: 1);
                                      }
                                      final track = tracks[index ~/ 2];
                                      return TrackRowTile(
                                        track: track,
                                        index: index ~/ 2 + 1,
                                        isPlaying: playback.isPlaying &&
                                            playingId == track.id,
                                        onTap: () => controller.queueAlbum(
                                          widget.album.id,
                                          startTrackId: track.id,
                                        ),
                                        onLike: () => controller.toggleLike(track),
                                      );
                                    },
                                    childCount: tracks.length * 2 - 1,
                                  ),
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
        ],
      ),
    );
  }
}
