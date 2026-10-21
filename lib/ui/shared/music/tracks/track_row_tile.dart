import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_overflow_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_add_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/svg_asset_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/like_icon_button.dart';

const double _trackActionButtonExtent = 38;

class TrackRowTile extends StatefulWidget {
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
  final Widget? albumArtOverlay;
  final Widget? leading;
  final bool showIndex;
  final bool actionsInMenu;

  const TrackRowTile({
    super.key,
    required this.track,
    required this.index,
    this.isPlaying = false,
    this.selectionMode = false,
    this.selected = false,
    this.offlineDownload,
    this.showAlbumArt = false,
    this.subtitle,
    this.trailing,
    this.showDuration = true,
    this.albumArtUrl,
    this.albumArtHeaders,
    this.albumArtOverlay,
    this.leading,
    this.showIndex = true,
    this.actionsInMenu = false,
    this.onTap,
    this.onLongPress,
    this.onAddToPlaylist,
    this.onDownload,
    this.onRemoveDownload,
    this.onLike,
    this.onDelete,
    this.onSelectionToggle,
    this.onSelectionModeRequested,
  });

  static List<ObsidianMenuAction> menuActionsFor({
    required Track track,
    OfflineTrackDownload? offlineDownload,
    VoidCallback? onLike,
    VoidCallback? onDownload,
    VoidCallback? onRemoveDownload,
    VoidCallback? onAddToPlaylist,
    VoidCallback? onDelete,
  }) {
    final removing = offlineDownload?.status == OfflineDownloadStatus.removing;
    final showDownload = offlineDownload?.status == OfflineDownloadStatus.downloaded
        ? onRemoveDownload != null
        : onDownload != null || offlineDownload != null;

    return [
      if (onLike != null)
        ObsidianMenuAction(
          label: track.liked ? 'Unlike' : 'Like',
          icon: track.liked ? null : PhonoliteIcons.heart,
          iconWidget: track.liked ? const SvgAssetIcon(assetName: 'assets/icons/lucide/heart-filled.svg') : null,
          isActive: track.liked,
          onTap: removing ? null : onLike,
        ),
      if (showDownload)
        _DownloadStatusButton(
          download: offlineDownload,
          onDownload: onDownload,
          onRemoveDownload: onRemoveDownload,
          isCompact: false,
        ).menuAction,
      if (onAddToPlaylist != null)
        ObsidianMenuAction(
          label: 'Add to playlist',
          iconWidget: const PlaylistAddIcon(),
          onTap: removing ? null : onAddToPlaylist,
        ),
      if (onDelete != null)
        ObsidianMenuAction(
          label: 'Delete',
          icon: PhonoliteIcons.trash2,
          variant: TechButtonVariant.danger,
          onTap: removing ? null : onDelete,
        ),
    ];
  }

  @override
  State<TrackRowTile> createState() => _TrackRowTileState();
}

class _TrackRowTileState extends State<TrackRowTile> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.isPlaying) {
      _startBars();
    }
  }

  @override
  void didUpdateWidget(covariant TrackRowTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startBars();
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

  void _startBars() {
    // Most rows never play. Allocate a ticker only when this row needs bars,
    // and keep it for subsequent pause/resume transitions.
    (_controller ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 900))).repeat();
  }

  Widget _leadingContent(ThemeData theme, {required bool isCompact, required bool isDeleting}) {
    if (widget.selectionMode) {
      return LucideCheckbox(
        value: widget.selected,
        onChanged: widget.onSelectionToggle == null || isDeleting ? null : (_) => widget.onSelectionToggle!(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: ObsidianPalette.border),
        activeColor: ObsidianPalette.gold,
      );
    }

    if (widget.isPlaying) {
      return _NowPlayingBars(controller: _controller ?? kAlwaysDismissedAnimation);
    }

    if (widget.leading != null) {
      return widget.leading!;
    }

    if (widget.showIndex) {
      return Text(
        widget.index.toString().padLeft(2, '0'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: isCompact ? 12 : null,
          color: ObsidianPalette.gold,
          letterSpacing: isCompact ? 0.8 : 1.2,
        ),
      );
    }

    return const SizedBox.shrink();
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
    if (!widget.showAlbumArt || hasLocalCover || controller == null || !canLoadRemoteArt) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = isCompactListWidth(context);
    final actionsInMenu = widget.actionsInMenu || ObsidianModalScope.isCompact(context);

    final explicitCoverUrl = widget.albumArtUrl?.trim();
    final controller = widget.showAlbumArt && (explicitCoverUrl == null || explicitCoverUrl.isEmpty)
        ? _maybeAppController(context)
        : null;
    final albumId = widget.track.albumId?.trim() ?? '';
    final canLoadRemoteArt = controller?.authState.isAuthorized == true;
    final localCoverPath = widget.track.albumArtPath?.trim();
    final hasLocalCover = localCoverPath != null && localCoverPath.isNotEmpty;
    final String? coverUrl;

    if (widget.showAlbumArt && explicitCoverUrl != null && explicitCoverUrl.isNotEmpty) {
      coverUrl = explicitCoverUrl;
    } else if (widget.showAlbumArt && hasLocalCover) {
      coverUrl = localCoverPath;
    } else {
      coverUrl = widget.showAlbumArt && albumId.isNotEmpty && canLoadRemoteArt
          ? controller?.catalog.buildAlbumCoverUrl(albumId)
          : null;
    }

    final headers =
        widget.albumArtHeaders ??
        _fallbackAlbumArtHeaders(controller, hasLocalCover: hasLocalCover, canLoadRemoteArt: canLoadRemoteArt);

    final selectionMode = widget.selectionMode;
    final showLeading = selectionMode || widget.isPlaying || widget.leading != null || widget.showIndex;
    final isDeleting = widget.offlineDownload?.status == OfflineDownloadStatus.removing;
    final showDownloadStatus = widget.offlineDownload?.status == OfflineDownloadStatus.downloaded
        ? widget.onRemoveDownload != null
        : widget.onDownload != null || widget.offlineDownload != null;

    final downloadButton = _DownloadStatusButton(
      download: widget.offlineDownload,
      onDownload: widget.onDownload,
      onRemoveDownload: widget.onRemoveDownload,
      isCompact: isCompact,
    );

    final overflowActions = actionsInMenu && !selectionMode
        ? TrackRowTile.menuActionsFor(
            track: widget.track,
            offlineDownload: widget.offlineDownload,
            onLike: widget.onLike,
            onDownload: widget.onDownload,
            onRemoveDownload: widget.onRemoveDownload,
            onAddToPlaylist: widget.onAddToPlaylist,
            onDelete: widget.onDelete,
          )
        : const <ObsidianMenuAction>[];
    final double leadingWidth;

    if (isCompact) {
      leadingWidth = selectionMode || widget.index >= 100 ? 28.0 : 22.0;
    } else {
      leadingWidth = 32.0;
    }

    final leadingGap = isCompact ? 4.0 : 8.0;
    final artSize = isCompact ? 32.0 : 42.0;
    final artGap = isCompact ? 8.0 : 12.0;
    final actionGap = isCompact ? 0.0 : 6.0;
    final actionIconSize = isCompact ? 18.0 : 22.0;

    Widget sizedAction(Widget child) => isCompact ? SizedBox.square(dimension: 44, child: child) : child;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: isCompact ? 13 : null,
      letterSpacing: isCompact ? 0.2 : 0.6,
      height: isCompact ? 1.25 : null,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: isCompact ? 11 : null,
      letterSpacing: isCompact ? 0 : null,
      height: isCompact ? 1.25 : null,
      color: ObsidianPalette.textMuted,
    );

    final VoidCallback? onTap;
    final VoidCallback? onLongPress;

    if (isDeleting) {
      onTap = null;
      onLongPress = null;
    } else {
      onTap = selectionMode ? widget.onSelectionToggle : widget.onTap;
      onLongPress = selectionMode ? widget.onSelectionToggle : widget.onSelectionModeRequested ?? widget.onLongPress;
    }

    return ObsidianHoverRow(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isDeleting ? 0.45 : 1,
        child: Row(
          children: [
            if (showLeading) ...[
              SizedBox(
                width: leadingWidth,
                child: Center(
                  heightFactor: 1,
                  child: _leadingContent(theme, isCompact: isCompact, isDeleting: isDeleting),
                ),
              ),
              SizedBox(width: leadingGap),
            ],
            if (widget.showAlbumArt) ...[
              SizedBox.square(
                dimension: artSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AlbumArt(title: widget.track.album, size: artSize, imageUrl: coverUrl, headers: headers),
                    if (widget.albumArtOverlay != null)
                      Positioned.fill(child: IgnorePointer(child: widget.albumArtOverlay!)),
                  ],
                ),
              ),
              SizedBox(width: artGap),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                  SizedBox(height: isCompact ? 1 : 2),
                  Text(
                    widget.subtitle ?? _artistAlbumLine(widget.track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ],
              ),
            ),
            if (!selectionMode && widget.trailing != null)
              widget.trailing!
            else ...[
              if (widget.showDuration && !isCompact) ...[
                Text(
                  _formatDuration(widget.track.durationMs),
                  style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.0, color: ObsidianPalette.textMuted),
                ),
                const SizedBox(width: 8),
              ],
              if (!selectionMode && !actionsInMenu && showDownloadStatus) ...[
                downloadButton,
                SizedBox(width: actionGap),
              ],
              if (!selectionMode && !actionsInMenu && !isCompact && widget.onAddToPlaylist != null) ...[
                ObsidianHudIconButton(
                  iconWidget: const PlaylistAddIcon(),
                  onPressed: isDeleting ? null : widget.onAddToPlaylist,
                  size: 22,
                ),
                SizedBox(width: actionGap),
              ],
              if (!selectionMode && !actionsInMenu)
                sizedAction(
                  LikeIconButton(
                    isLiked: widget.track.liked,
                    onPressed: isDeleting ? null : widget.onLike,
                    size: actionIconSize,
                  ),
                ),
              if (!selectionMode && !actionsInMenu && !isCompact && widget.onDelete != null) ...[
                SizedBox(width: actionGap),
                ObsidianHudIconButton(
                  icon: PhonoliteIcons.trash2,
                  onPressed: isDeleting ? null : widget.onDelete,
                  size: 22,
                ),
              ],
              if (overflowActions.isNotEmpty) ...[
                SizedBox(width: actionGap),
                sizedAction(
                  ObsidianOverflowActionButton(
                    tooltip: 'Track actions',
                    modalTitle: widget.track.title,
                    actions: overflowActions,
                    size: actionIconSize,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadStatusButton extends StatelessWidget {
  final OfflineTrackDownload? download;
  final VoidCallback? onDownload;
  final VoidCallback? onRemoveDownload;
  final bool isCompact;

  const _DownloadStatusButton({
    required this.download,
    required this.onDownload,
    required this.onRemoveDownload,
    required this.isCompact,
  });

  VoidCallback? get action => switch (download?.status) {
    OfflineDownloadStatus.downloaded => onRemoveDownload,
    OfflineDownloadStatus.queued ||
    OfflineDownloadStatus.preparing ||
    OfflineDownloadStatus.downloading ||
    OfflineDownloadStatus.validating ||
    OfflineDownloadStatus.removing => null,
    OfflineDownloadStatus.paused ||
    OfflineDownloadStatus.failed ||
    OfflineDownloadStatus.corrupt ||
    OfflineDownloadStatus.canceled ||
    null => onDownload,
  };

  String get tooltip => switch (download?.status) {
    OfflineDownloadStatus.removing => 'Removing download',
    OfflineDownloadStatus.downloaded => onRemoveDownload == null ? 'Downloaded' : 'Remove download',
    OfflineDownloadStatus.downloading => 'Downloading',
    OfflineDownloadStatus.validating => 'Validating download',
    OfflineDownloadStatus.preparing => 'Preparing download',
    OfflineDownloadStatus.queued => 'Queued download',
    OfflineDownloadStatus.failed => 'Retry download',
    OfflineDownloadStatus.paused ||
    OfflineDownloadStatus.corrupt ||
    OfflineDownloadStatus.canceled ||
    null => 'Download',
  };

  IconData get icon => switch (download?.status) {
    OfflineDownloadStatus.downloaded => onRemoveDownload == null ? PhonoliteIcons.circleCheck : PhonoliteIcons.trash2,
    OfflineDownloadStatus.removing => PhonoliteIcons.trash2,
    OfflineDownloadStatus.queued => PhonoliteIcons.clock,
    OfflineDownloadStatus.preparing ||
    OfflineDownloadStatus.downloading ||
    OfflineDownloadStatus.paused ||
    OfflineDownloadStatus.validating ||
    OfflineDownloadStatus.failed ||
    OfflineDownloadStatus.corrupt ||
    OfflineDownloadStatus.canceled ||
    null => PhonoliteIcons.download,
  };

  ObsidianMenuAction get menuAction => ObsidianMenuAction(
    label: tooltip,
    icon: download?.status == OfflineDownloadStatus.preparing ? null : icon,
    iconWidget: download?.status == OfflineDownloadStatus.preparing ? const ReloadIcon() : null,
    variant: download?.isDownloaded == true && onRemoveDownload != null
        ? TechButtonVariant.danger
        : TechButtonVariant.standard,
    onTap: action,
  );

  Widget _statusIndicator({
    required double iconSize,
    required Color color,
    required double? progress,
    required bool showProgressRing,
    required bool preparing,
  }) {
    if (showProgressRing) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 2,
          color: ObsidianPalette.gold,
          backgroundColor: ObsidianPalette.border.withValues(alpha: 0.4),
        ),
      );
    }

    if (preparing) {
      return IconTheme.merge(
        data: IconThemeData(color: color, size: iconSize),
        child: const ReloadIcon(),
      );
    }

    return Icon(icon, color: color, size: iconSize);
  }

  @override
  Widget build(BuildContext context) {
    final status = download?.status;
    final iconSize = isCompact ? 18.0 : 22.0;
    final preparing = status == OfflineDownloadStatus.preparing;
    final downloading = status == OfflineDownloadStatus.downloading;
    final downloaded = status == OfflineDownloadStatus.downloaded;
    final failed = status == OfflineDownloadStatus.failed;
    final Color color;

    if (downloaded) {
      color = onRemoveDownload == null ? ObsidianPalette.gold : Theme.of(context).colorScheme.error;
    } else {
      color = failed ? Theme.of(context).colorScheme.error : ObsidianPalette.textMuted;
    }

    final progress = download?.progress;
    final showProgressRing = downloading;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: withButtonHaptic(action),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: isCompact ? 44 : _trackActionButtonExtent,
          height: isCompact ? 44 : _trackActionButtonExtent,
          child: Center(
            child: _statusIndicator(
              iconSize: iconSize,
              color: color,
              progress: progress,
              showProgressRing: showProgressRing,
              preparing: preparing,
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBars extends StatelessWidget {
  final Animation<double> controller;

  const _NowPlayingBars({required this.controller});

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
  final double height;

  const _Bar({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(color: const Color(0xFFFFA33A), borderRadius: BorderRadius.circular(2)),
    );
  }
}
