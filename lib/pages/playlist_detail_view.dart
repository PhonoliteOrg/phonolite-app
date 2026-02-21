import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/track_row_tile.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/navigation/command_link_button.dart';
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
        final playlist = (snapshot.data ?? [])
            .firstWhere((item) => item.id == widget.playlistId,
                orElse: () => Playlist(
                      id: widget.playlistId,
                      name: 'Playlist',
                      trackIds: const [],
                    ));
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
                        return SliverList(
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
                                onTap: () => controller.queuePlaylist(
                                  widget.playlistId,
                                  startTrackId: track.id,
                                ),
                                onLike: () => controller.toggleLike(track),
                                onDelete: () => controller.removeTrackFromPlaylist(
                                  playlist,
                                  track,
                                ),
                              );
                            },
                            childCount: tracks.length * 2 - 1,
                          ),
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
          density: isCompact ? TechButtonDensity.compact : TechButtonDensity.standard,
        );
        final deleteButton = TechButton(
          label: 'Delete',
          icon: Icons.delete,
          onTap: onDelete,
          variant: TechButtonVariant.danger,
          density: isCompact ? TechButtonDensity.compact : TechButtonDensity.standard,
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaylistMarqueeText(
                text: name.toUpperCase(),
                style: nameStyle,
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
            Expanded(
              child: Text(
                name.toUpperCase(),
                style: nameStyle,
              ),
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                renameButton,
                const SizedBox(width: 10),
                deleteButton,
              ],
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

class _PlaylistMarqueeText extends StatefulWidget {
  const _PlaylistMarqueeText({
    required this.text,
    required this.style,
    this.velocity = 28,
    this.gap = 32,
    this.pause = const Duration(milliseconds: 900),
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final double gap;
  final Duration pause;

  @override
  State<_PlaylistMarqueeText> createState() => _PlaylistMarqueeTextState();
}

class _PlaylistMarqueeTextState extends State<_PlaylistMarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _running = false;
  bool _shouldScroll = false;

  @override
  void didUpdateWidget(covariant _PlaylistMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLoop());
    }
  }

  @override
  void dispose() {
    _running = false;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startLoop() async {
    if (_running || !_shouldScroll) {
      return;
    }
    _running = true;
    await Future.delayed(const Duration(milliseconds: 200));
    while (mounted && _running) {
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final position = _controller.position;
      final max = position.maxScrollExtent;
      if (max <= 0) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }
      await Future.delayed(widget.pause);
      if (!_controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final distance = max - _controller.position.pixels;
      final durationMs = (distance / widget.velocity * 1000).round();
      await _controller.animateTo(
        max,
        duration: Duration(milliseconds: durationMs.clamp(1, 60000)),
        curve: Curves.linear,
      );
      await Future.delayed(widget.pause);
      if (!_running) {
        break;
      }
      _controller.jumpTo(0);
    }
  }

  void _setShouldScroll(bool value) {
    if (_shouldScroll == value) {
      return;
    }
    _shouldScroll = value;
    if (!_shouldScroll) {
      _running = false;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    } else {
      _startLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final shouldScroll = painter.width > constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _setShouldScroll(shouldScroll);
          }
        });

        if (!shouldScroll) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: widget.style, maxLines: 1),
                  SizedBox(width: widget.gap),
                  Text(widget.text, style: widget.style, maxLines: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
