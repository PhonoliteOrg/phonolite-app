import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_analysis_section.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_kpi_grid.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_top_tracks_section.dart';

/// Listening summaries and analysis. The surrounding page owns its toolbar and
/// scrolling viewport, so this content also works within other page assemblies.
class StatsCardsContent extends StatelessWidget {
  final StatsResponse stats;
  final String? Function(StatsItem)? artistCoverUrl;
  final Map<String, String> artistImageHeaders;
  final ValueChanged<StatsItem>? onArtistTap;
  final ValueChanged<StatsTrack>? onTrackTap;

  const StatsCardsContent({
    super.key,
    required this.stats,
    this.artistImageHeaders = const {},
    this.artistCoverUrl,
    this.onArtistTap,
    this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsKpiGrid(stats: stats),
        if (stats.topTracks.isEmpty && stats.totalMinutes == 0 && stats.totalListeningMs == 0) ...[
          SizedBox(height: s(12)),
          StatsEmptyText('No listening in this period yet.'),
        ],
        SizedBox(height: s(28)),
        StatsAnalysisSection(
          stats: stats,
          artistCoverUrl: artistCoverUrl,
          artistImageHeaders: artistImageHeaders,
          onArtistTap: onArtistTap,
        ),
        SizedBox(height: s(28)),
        StatsTopTracksSection(tracks: stats.topTracks, onTrackTap: onTrackTap),
      ],
    );
  }
}
