import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/like_icon_button.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

class TrackRowTile extends StatefulWidget {
  const TrackRowTile({
    super.key,
    required this.track,
    required this.index,
    this.isPlaying = false,
    this.onTap,
    this.onLongPress,
    this.onLike,
    this.onDelete,
  });

  final Track track;
  final int index;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onLike;
  final VoidCallback? onDelete;

  @override
  State<TrackRowTile> createState() => _TrackRowTileState();
}

class _TrackRowTileState extends State<TrackRowTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller!.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant TrackRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller?.repeat();
      } else {
        _controller?.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: widget.isPlaying
                  ? _NowPlayingBars(
                      controller: _controller ?? kAlwaysDismissedAnimation,
                    )
                  : Text(
                      widget.index.toString().padLeft(2, '0'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ObsidianPalette.gold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _artistAlbumLine(widget.track),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(widget.track.durationMs),
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 1.0,
              color: ObsidianPalette.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          LikeIconButton(
            isLiked: widget.track.liked,
            onPressed: widget.onLike,
            size: 22,
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(width: 6),
            ObsidianHudIconButton(
              icon: Icons.delete_outline_rounded,
              onPressed: widget.onDelete,
              size: 22,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int durationMs) {
    final seconds = (durationMs / 1000).round();
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  String _artistAlbumLine(Track track) {
    final artist = track.artist.trim();
    final album = track.album.trim();
    if (artist.isEmpty) {
      return album;
    }
    if (album.isEmpty) {
      return artist;
    }
    return '$artist • $album';
  }
}

class _NowPlayingBars extends StatelessWidget {
  const _NowPlayingBars({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value * 2 * math.pi;
        final heights = <double>[
          6 + 8 * (0.5 + 0.5 * math.sin(t)),
          6 + 10 * (0.5 + 0.5 * math.sin(t + 1.6)),
          6 + 7 * (0.5 + 0.5 * math.sin(t + 3.2)),
        ];
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Bar(height: heights[0]),
            const SizedBox(width: 2),
            _Bar(height: heights[1]),
            const SizedBox(width: 2),
            _Bar(height: heights[2]),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFFA33A),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}


