import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_cards_content.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_header.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shell/page_body.dart';

export 'package:phonolite_app/ui/features/listening_stats/widgets/stats_cards_content.dart';
export 'package:phonolite_app/ui/features/listening_stats/widgets/stats_history_status.dart';

/// Standalone statistics overview. Pages can instead supply [StatsHeader] and
/// [StatsCardsContent] to their base assembly as separate toolbar and body slots.
class StatsCards extends StatelessWidget {
  final StatsResponse stats;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback? onRefresh;
  final Widget? historyStatus;
  final String? Function(StatsItem)? artistCoverUrl;
  final Map<String, String> artistImageHeaders;
  final ValueChanged<StatsItem>? onArtistTap;
  final ValueChanged<StatsTrack>? onTrackTap;

  const StatsCards({
    super.key,
    required this.stats,
    required this.onYearChanged,
    required this.onMonthChanged,
    this.historyStatus,
    this.artistImageHeaders = const {},
    this.onRefresh,
    this.artistCoverUrl,
    this.onArtistTap,
    this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    // These cards and selectors occupy disjoint rectangles. Their matching blur
    // can sample the backdrop once instead of once for every panel.
    return BackdropGroup(
      child: PageLayout(
        navbarPadding: EdgeInsets.only(bottom: s(20)),
        navbar: StatsHeader(
          stats: stats,
          onYearChanged: onYearChanged,
          onMonthChanged: onMonthChanged,
          onRefresh: onRefresh,
          historyStatus: historyStatus,
        ),
        body: PageBody.scroll(
          padding: EdgeInsets.fromLTRB(20, 16, 20, s(20)),
          child: StatsCardsContent(
            stats: stats,
            artistCoverUrl: artistCoverUrl,
            artistImageHeaders: artistImageHeaders,
            onArtistTap: onArtistTap,
            onTrackTap: onTrackTap,
          ),
        ),
      ),
    );
  }
}
