import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../../entities/offline_library.dart';
import 'track_row_tile.dart';

class TrackSliverList extends StatelessWidget {
  const TrackSliverList({
    super.key,
    required this.tracks,
    required this.isPlayingTrack,
    this.onTrackTap,
    this.onTrackLongPress,
    this.onTrackAddToPlaylist,
    this.onTrackDownload,
    this.onTrackRemoveDownload,
    this.onTrackLike,
    this.onTrackDelete,
    this.selectionMode = false,
    this.canSelectTrack,
    this.isTrackSelected,
    this.onTrackSelectionToggle,
    this.onTrackSelectionModeRequested,
    this.offlineDownloadForTrack,
    this.showAlbumArt = false,
  });

  final List<Track> tracks;
  final bool Function(Track track) isPlayingTrack;
  final ValueChanged<Track>? onTrackTap;
  final ValueChanged<Track>? onTrackLongPress;
  final ValueChanged<Track>? onTrackAddToPlaylist;
  final ValueChanged<Track>? onTrackDownload;
  final ValueChanged<Track>? onTrackRemoveDownload;
  final ValueChanged<Track>? onTrackLike;
  final ValueChanged<Track>? onTrackDelete;
  final bool selectionMode;
  final bool Function(Track track)? canSelectTrack;
  final bool Function(Track track)? isTrackSelected;
  final ValueChanged<Track>? onTrackSelectionToggle;
  final ValueChanged<Track>? onTrackSelectionModeRequested;
  final OfflineTrackDownload? Function(Track track)? offlineDownloadForTrack;
  final bool showAlbumArt;

  @override
  Widget build(BuildContext context) {
    final itemCount = tracks.isEmpty ? 0 : tracks.length * 2 - 1;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index.isOdd) {
          return const Divider(height: 1);
        }
        final track = tracks[index ~/ 2];
        final offlineDownload = offlineDownloadForTrack?.call(track);
        final isDeleting =
            offlineDownload?.status == OfflineDownloadStatus.removing;
        final selectable = (canSelectTrack?.call(track) ?? true) && !isDeleting;
        return TrackRowTile(
          track: track,
          index: index ~/ 2 + 1,
          showAlbumArt: showAlbumArt,
          isPlaying: isPlayingTrack(track),
          onTap: onTrackTap == null ? null : () => onTrackTap!(track),
          onLongPress: onTrackLongPress == null
              ? null
              : () => onTrackLongPress!(track),
          onAddToPlaylist: onTrackAddToPlaylist == null
              ? null
              : () => onTrackAddToPlaylist!(track),
          onDownload: onTrackDownload == null
              ? null
              : () => onTrackDownload!(track),
          onRemoveDownload: onTrackRemoveDownload == null
              ? null
              : () => onTrackRemoveDownload!(track),
          onLike: onTrackLike == null ? null : () => onTrackLike!(track),
          onDelete: onTrackDelete == null ? null : () => onTrackDelete!(track),
          selectionMode: selectionMode,
          selected: isTrackSelected?.call(track) ?? false,
          onSelectionToggle: selectable && onTrackSelectionToggle != null
              ? () => onTrackSelectionToggle!(track)
              : null,
          onSelectionModeRequested:
              selectable && onTrackSelectionModeRequested != null
              ? () => onTrackSelectionModeRequested!(track)
              : null,
          offlineDownload: offlineDownload,
        );
      }, childCount: itemCount),
    );
  }
}
