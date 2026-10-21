import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_row_tile.dart';
import 'package:phonolite_app/ui/structures/sections/base_sliver_section.dart';

class LikedSection extends BaseSliverSection {
  final String? title;
  final List<Track> tracks;
  final String emptyTitle;
  final PlaybackState playback;
  final ValueChanged<Track> onTap;
  final ValueChanged<Track> onLike;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track>? onDownload;
  final OfflineTrackDownload? Function(Track track) offlineDownloadForTrack;
  final bool selectionMode;
  final bool Function(Track track) canSelectTrack;
  final bool Function(Track track) isTrackSelected;
  final ValueChanged<Track> onSelectionToggle;
  final ValueChanged<Track> onSelectionModeRequested;

  const LikedSection({
    super.key,
    required this.title,
    required this.tracks,
    required this.emptyTitle,
    required this.playback,
    required this.onTap,
    required this.onLike,
    required this.onAddToPlaylist,
    required this.offlineDownloadForTrack,
    required this.selectionMode,
    required this.canSelectTrack,
    required this.isTrackSelected,
    required this.onSelectionToggle,
    required this.onSelectionModeRequested,
    this.onDownload,
  });

  @override
  String? get sectionTitle => title;

  @override
  Widget sectionSliver(BuildContext context) {
    final playingId = playback.track?.id;

    return tracks.isEmpty
        ? SliverToBoxAdapter(child: _LikedEmptyText(title: emptyTitle))
        : SliverList.separated(
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final track = tracks[index];

              return TrackRowTile(
                track: track,
                index: index + 1,
                showAlbumArt: true,
                isPlaying: playback.isPlaying && playingId == track.id,
                onTap: () => onTap(track),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onDownload: onDownload == null ? null : () => onDownload!(track),
                onLike: () => onLike(track),
                selectionMode: selectionMode,
                selected: isTrackSelected(track),
                onSelectionToggle: canSelectTrack(track) ? () => onSelectionToggle(track) : null,
                onSelectionModeRequested: canSelectTrack(track) ? () => onSelectionModeRequested(track) : null,
                offlineDownload: offlineDownloadForTrack(track),
              );
            },
          );
  }
}

class _LikedEmptyText extends StatelessWidget {
  final String title;

  const _LikedEmptyText({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 0.6),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
