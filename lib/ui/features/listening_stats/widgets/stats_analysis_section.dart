import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_top_artists_section.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_top_genres_section.dart';

class StatsAnalysisSection extends StatelessWidget {
  final StatsResponse stats;
  final String? Function(StatsItem)? artistCoverUrl;
  final Map<String, String> artistImageHeaders;
  final ValueChanged<StatsItem>? onArtistTap;

  const StatsAnalysisSection({
    super.key,
    required this.stats,
    required this.artistCoverUrl,
    required this.artistImageHeaders,
    required this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final isWide = MediaQuery.of(context).size.width >= 900;

    final left = StatsTopGenresSection(
      genres: stats.topGenres,
      totalListeningMs: stats.totalListeningMs > 0 ? stats.totalListeningMs : stats.totalMinutes * 60000,
      otherListeningMs: stats.otherGenreListeningMs,
      unclassifiedListeningMs: stats.unclassifiedListeningMs,
      fillHeight: isWide,
    );

    final right = StatsTopArtistsSection(
      artists: stats.topArtists,
      coverUrl: artistCoverUrl,
      headers: artistImageHeaders,
      onArtistTap: onArtistTap,
    );

    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            SizedBox(width: s(20)),
            Expanded(child: right),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        SizedBox(height: s(24)),
        right,
      ],
    );
  }
}
