import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/library_helpers.dart';
import '../../entities/app_controller.dart';
import '../../entities/models.dart';
import '../../entities/offline_library.dart';
import '../layouts/app_scope.dart';
import '../ui/hover_row.dart';
import '../ui/like_icon_button.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';
import 'album_art.dart';

const double _trackActionButtonExtent = 38;

class TrackRowTile extends StatefulWidget {
  const TrackRowTile({
    super.key,
    required this.track,
    required this.index,
    this.isPlaying = false,
    this.onTap,
    this.onLongPress,
    this.onAddToPlaylist,
    this.onDownload,
    this.onRemoveDownload,
    this.onLike,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
    this.onSelectionModeRequested,
    this.offlineDownload,
    this.showAlbumArt = false,
    this.subtitle,
    this.trailing,
    this.showDuration = true,
    this.albumArtUrl,
    this.albumArtHeaders,
    this.leading,
    this.showIndex = true,
  });

  final Track track;
  final int index;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onDownload;
  final VoidCallback? onRemoveDownload;
  final VoidCallback? onLike;
  final VoidCallback? onDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionToggle;
  final VoidCallback? onSelectionModeRequested;
  final OfflineTrackDownload? offlineDownload;
  final bool showAlbumArt;
  final String? subtitle;
  final Widget? trailing;
  final bool showDuration;
  final String? albumArtUrl;
  final Map<String, String>? albumArtHeaders;
  final Widget? leading;
  final bool showIndex;

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
    final explicitCoverUrl = widget.albumArtUrl?.trim();
    final controller =
        widget.showAlbumArt &&
            (explicitCoverUrl == null || explicitCoverUrl.isEmpty)
        ? _maybeAppController(context)
        : null;
    final albumId = widget.track.albumId?.trim() ?? '';
    final canLoadRemoteArt = controller?.authState.isAuthorized == true;
    final localCoverPath = widget.track.albumArtPath?.trim();
    final hasLocalCover = localCoverPath != null && localCoverPath.isNotEmpty;
    final coverUrl =
        widget.showAlbumArt &&
            explicitCoverUrl != null &&
            explicitCoverUrl.isNotEmpty
        ? explicitCoverUrl
        : widget.showAlbumArt && hasLocalCover
        ? localCoverPath
        : widget.showAlbumArt && albumId.isNotEmpty && canLoadRemoteArt
        ? controller?.connection.buildAlbumCoverUrl(albumId)
        : null;
    final headers =
        widget.albumArtHeaders ??
        _fallbackAlbumArtHeaders(
          controller,
          hasLocalCover: hasLocalCover,
          canLoadRemoteArt: canLoadRemoteArt,
        );

    final selectionMode = widget.selectionMode;
    final isDeleting =
        widget.offlineDownload?.status == OfflineDownloadStatus.removing;

    return ObsidianHoverRow(
      onTap: isDeleting
          ? null
          : selectionMode
          ? widget.onSelectionToggle
          : widget.onTap,
      onLongPress: isDeleting
          ? null
          : selectionMode
          ? widget.onSelectionToggle
          : widget.onSelectionModeRequested ?? widget.onLongPress,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isDeleting ? 0.45 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Center(
                child: selectionMode
                    ? Checkbox(
                        value: widget.selected,
                        onChanged:
                            widget.onSelectionToggle == null || isDeleting
                            ? null
                            : (_) => widget.onSelectionToggle!(),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: ObsidianPalette.border),
                        activeColor: ObsidianPalette.gold,
                      )
                    : widget.isPlaying
                    ? _NowPlayingBars(
                        controller: _controller ?? kAlwaysDismissedAnimation,
                      )
                    : widget.leading != null
                    ? widget.leading!
                    : widget.showIndex
                    ? Text(
                        widget.index.toString().padLeft(2, '0'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ObsidianPalette.gold,
                          letterSpacing: 1.2,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.showAlbumArt) ...[
              AlbumArt(
                title: widget.track.album,
                size: 42,
                imageUrl: coverUrl,
                headers: headers,
              ),
              const SizedBox(width: 12),
            ],
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
                    widget.subtitle ?? _artistAlbumLine(widget.track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!selectionMode && widget.trailing != null)
              widget.trailing!
            else ...[
              if (widget.showDuration) ...[
                Text(
                  _formatDuration(widget.track.durationMs),
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.0,
                    color: ObsidianPalette.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!selectionMode &&
                  (widget.onDownload != null ||
                      widget.offlineDownload != null)) ...[
                _DownloadStatusButton(
                  download: widget.offlineDownload,
                  onDownload: widget.onDownload,
                  onRemoveDownload: widget.onRemoveDownload,
                ),
                const SizedBox(width: 6),
              ],
              if (!selectionMode && widget.onAddToPlaylist != null) ...[
                ObsidianHudIconButton(
                  icon: Icons.playlist_add_rounded,
                  onPressed: isDeleting ? null : widget.onAddToPlaylist,
                  size: 22,
                ),
                const SizedBox(width: 6),
              ],
              if (!selectionMode)
                LikeIconButton(
                  isLiked: widget.track.liked,
                  onPressed: isDeleting ? null : widget.onLike,
                  size: 22,
                ),
              if (!selectionMode && widget.onDelete != null) ...[
                const SizedBox(width: 6),
                ObsidianHudIconButton(
                  icon: Icons.delete_outline_rounded,
                  onPressed: isDeleting ? null : widget.onDelete,
                  size: 22,
                ),
              ],
            ],
          ],
        ),
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
    return '$artist / $album';
  }

  Map<String, String> _fallbackAlbumArtHeaders(
    AppController? controller, {
    required bool hasLocalCover,
    required bool canLoadRemoteArt,
  }) {
    if (!widget.showAlbumArt ||
        hasLocalCover ||
        controller == null ||
        !canLoadRemoteArt) {
      return const <String, String>{};
    }
    return authHeaders(controller);
  }

  AppController? _maybeAppController(BuildContext context) {
    try {
      return AppScope.of(context);
    } catch (_) {
      return null;
    }
  }
}

class _DownloadStatusButton extends StatelessWidget {
  const _DownloadStatusButton({
    required this.download,
    required this.onDownload,
    required this.onRemoveDownload,
  });

  final OfflineTrackDownload? download;
  final VoidCallback? onDownload;
  final VoidCallback? onRemoveDownload;

  @override
  Widget build(BuildContext context) {
    final status = download?.status;
    final queued = status == OfflineDownloadStatus.queued;
    final preparing = status == OfflineDownloadStatus.preparing;
    final downloading = status == OfflineDownloadStatus.downloading;
    final validating = status == OfflineDownloadStatus.validating;
    final busy = queued || preparing || downloading || validating;
    final removing = status == OfflineDownloadStatus.removing;
    final downloaded = status == OfflineDownloadStatus.downloaded;
    final failed = status == OfflineDownloadStatus.failed;
    final color = downloaded
        ? onRemoveDownload == null
              ? ObsidianPalette.gold
              : Theme.of(context).colorScheme.error
        : failed
        ? Theme.of(context).colorScheme.error
        : ObsidianPalette.textMuted;
    final progress = download?.progress;
    final showProgressRing = downloading;
    final action = downloaded
        ? onRemoveDownload
        : busy || removing
        ? null
        : onDownload;
    final tooltip = removing
        ? 'Removing download'
        : downloaded
        ? onRemoveDownload == null
              ? 'Downloaded'
              : 'Remove download'
        : downloading
        ? 'Downloading'
        : validating
        ? 'Validating download'
        : preparing
        ? 'Preparing download'
        : queued
        ? 'Queued download'
        : failed
        ? 'Retry download'
        : 'Download';

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: action,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _trackActionButtonExtent,
          height: _trackActionButtonExtent,
          child: Center(
            child: showProgressRing
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                      color: ObsidianPalette.gold,
                      backgroundColor: ObsidianPalette.border.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  )
                : Icon(
                    downloaded
                        ? onRemoveDownload == null
                              ? Icons.offline_pin_rounded
                              : Icons.delete_outline_rounded
                        : removing
                        ? Icons.delete_sweep_rounded
                        : validating
                        ? Icons.downloading_rounded
                        : preparing
                        ? Icons.sync_rounded
                        : queued
                        ? Icons.schedule_rounded
                        : downloading
                        ? Icons.downloading_rounded
                        : failed
                        ? Icons.download_for_offline_rounded
                        : Icons.download_for_offline_outlined,
                    color: color,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
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
