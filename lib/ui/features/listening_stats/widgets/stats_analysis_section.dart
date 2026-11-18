import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/data/models/listening_stats/stats_item.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_top_artists_section.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_top_genres_section.dart';

class StatsAnalysisSection extends StatelessWidget {
  final StatsResponse stats;
  final String? Function(StatsItem)? artistCoverUrl;
  final ValueChanged<StatsItem>? onArtistTap;

  const StatsAnalysisSection({super.key, required this.stats, required this.artistCoverUrl, required this.onArtistTap});

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final left = StatsTopGenresSection(
      genres: stats.topGenres,
      totalListeningMs: stats.totalListeningMs > 0 ? stats.totalListeningMs : stats.totalMinutes * 60000,
      otherListeningMs: stats.otherGenreListeningMs,
      unclassifiedListeningMs: stats.unclassifiedListeningMs,
      fillHeight: isWide,
    );

    final right = StatsTopArtistsSection(artists: stats.topArtists, coverUrl: artistCoverUrl, onArtistTap: onArtistTap);

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
