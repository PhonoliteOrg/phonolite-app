import 'package:flutter/material.dart';

import '../../entities/models.dart';
import 'track_row_tile.dart';

class TrackSliverList extends StatelessWidget {
  const TrackSliverList({
    super.key,
    required this.tracks,
    required this.isPlayingTrack,
    this.onTrackTap,
    this.onTrackLongPress,
    this.onTrackLike,
    this.onTrackDelete,
    this.showAlbumArt = false,
  });

  final List<Track> tracks;
  final bool Function(Track track) isPlayingTrack;
  final ValueChanged<Track>? onTrackTap;
  final ValueChanged<Track>? onTrackLongPress;
  final ValueChanged<Track>? onTrackLike;
  final ValueChanged<Track>? onTrackDelete;
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
        return TrackRowTile(
          track: track,
          index: index ~/ 2 + 1,
          showAlbumArt: showAlbumArt,
          isPlaying: isPlayingTrack(track),
          onTap: onTrackTap == null ? null : () => onTrackTap!(track),
          onLongPress: onTrackLongPress == null
              ? null
              : () => onTrackLongPress!(track),
          onLike: onTrackLike == null ? null : () => onTrackLike!(track),
          onDelete: onTrackDelete == null ? null : () => onTrackDelete!(track),
        );
      }, childCount: itemCount),
    );
  }
}
