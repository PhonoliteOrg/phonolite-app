import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_module_shell.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class StatsTopTracksSection extends StatelessWidget {
  final List<StatsTrack> tracks;
  final ValueChanged<StatsTrack>? onTrackTap;

  const StatsTopTracksSection({super.key, required this.tracks, required this.onTrackTap});

  @override
  Widget build(BuildContext context) {
    final topTracks = tracks.take(10).toList();

    return StatsModuleShell(
      title: 'MOST PLAYED TRACKS',
      child: Column(
        children: [
          if (topTracks.isEmpty)
            StatsEmptyText('No tracks yet.')
          else
            for (var i = 0; i < topTracks.length; i++)
              _TrackRow(
                key: topTracks[i].id.trim().isEmpty ? null : ValueKey('stats-track-${topTracks[i].id}'),
                onTap: onTrackTap == null || topTracks[i].id.trim().isEmpty ? null : () => onTrackTap!(topTracks[i]),
                rank: i + 1,
                title: topTracks[i].title,
                playCount: topTracks[i].plays,
              ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final int rank;
  final String title;
  final int playCount;
  final VoidCallback? onTap;

  const _TrackRow({super.key, required this.rank, required this.title, required this.playCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    return ObsidianHoverRow(
      onTap: onTap,
      borderWidth: s(2),
      padding: EdgeInsets.symmetric(vertical: s(10), horizontal: s(12)),
      hoverColor: Colors.white.withByteOpacity(0.05),
      child: Row(
        children: [
          SizedBox(
            width: s(46),
            child: Text(
              rank.toString().padLeft(2, '0'),
              style: GoogleFonts.rajdhani(fontSize: s(22), fontWeight: FontWeight.w700, color: ObsidianPalette.gold),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: s(0.6)),
            ),
          ),
          Text(
            '$playCount PLAYS',
            style: GoogleFonts.rajdhani(
              fontSize: s(12),
              fontWeight: FontWeight.w700,
              color: ObsidianPalette.gold,
              letterSpacing: s(1.2),
            ),
          ),
        ],
      ),
    );
  }
}
