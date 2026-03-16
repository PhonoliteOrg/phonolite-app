import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/marquee_text.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/tech_button.dart';

class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    controller.loadPlaylistTracks(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<Playlist>>(
      stream: controller.playlistsStream,
      initialData: controller.playlists,
      builder: (context, snapshot) {
        final playlist = (snapshot.data ?? []).firstWhere(
          (item) => item.id == widget.playlistId,
          orElse: () => Playlist(
            id: widget.playlistId,
            name: 'Playlist',
            trackIds: const [],
          ),
        );
        return Scaffold(
          backgroundColor: bgDark,
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: CommandLinkButton(
                    label: 'Back to playlists',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: _PlaylistBanner(
                    name: playlist.name,
                    onRename: () => _openRename(controller, playlist),
                    onDelete: () => _deletePlaylist(controller, playlist),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: StreamBuilder<List<Track>>(
                  stream: controller.playlistTracksStream,
                  initialData: controller.playlistTracks,
                  builder: (context, tracksSnapshot) {
                    final tracks = tracksSnapshot.data ?? [];
                    if (tracks.isEmpty) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: _EmptyPlaylistText()),
                      );
                    }
                    return StreamBuilder<PlaybackState>(
                      stream: controller.playbackStream,
                      initialData: controller.playbackState,
                      builder: (context, playbackSnapshot) {
                        final playback =
                            playbackSnapshot.data ?? controller.playbackState;
                        final playingId = playback.track?.id;
                        return TrackSliverList(
                          tracks: tracks,
                          isPlayingTrack: (track) =>
                              playback.isPlaying && playingId == track.id,
                          onTrackTap: (track) => controller.queuePlaylist(
                            widget.playlistId,
                            startTrackId: track.id,
                          ),
                          onTrackLike: controller.toggleLike,
                          onTrackDelete: (track) => controller
                              .removeTrackFromPlaylist(playlist, track),
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

  void _openRename(AppController controller, Playlist playlist) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Rename playlist',
        initialValue: playlist.name,
        onSubmit: (value) => controller.renamePlaylist(playlist.id, value),
      ),
    );
  }

  void _deletePlaylist(AppController controller, Playlist playlist) {
    controller.deletePlaylist(playlist.id);
    Navigator.of(context).pop();
  }
}

class _PlaylistBanner extends StatelessWidget {
  const _PlaylistBanner({
    required this.name,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final nameStyle = GoogleFonts.rajdhani(
          fontSize: isCompact ? 40 : 60,
          fontWeight: FontWeight.w700,
          height: 0.95,
          letterSpacing: 1.6,
        );
        final renameButton = TechButton(
          label: 'Rename',
          icon: Icons.edit,
          onTap: onRename,
          density: isCompact
              ? TechButtonDensity.compact
              : TechButtonDensity.standard,
        );
        final deleteButton = TechButton(
          label: 'Delete',
          icon: Icons.delete,
          onTap: onDelete,
          variant: TechButtonVariant.danger,
          density: isCompact
              ? TechButtonDensity.compact
              : TechButtonDensity.standard,
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(
                text: name.toUpperCase(),
                style: nameStyle,
                velocity: 28,
                gap: 32,
                pause: const Duration(milliseconds: 900),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [renameButton, deleteButton],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(name.toUpperCase(), style: nameStyle)),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [renameButton, const SizedBox(width: 10), deleteButton],
            ),
          ],
        );
      },
    );
  }
}

class _EmptyPlaylistText extends StatelessWidget {
  const _EmptyPlaylistText();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No tracks yet.',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: ObsidianPalette.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
