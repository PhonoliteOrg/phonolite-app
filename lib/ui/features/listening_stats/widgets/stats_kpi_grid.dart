import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class StatsKpiGrid extends StatelessWidget {
  final StatsResponse stats;

  const StatsKpiGrid({super.key, required this.stats});

  String? _tooltip(String label) => switch (label) {
    'TOTAL PLAYS' =>
      'A play counts after 30 seconds, or half of a shorter track. '
          'Brief listens still contribute to listening time and tracks listened.',
    'TRACKS LISTENED' => 'Distinct tracks with any audio played, including brief listens.',
    _ => null,
  };

  String _listeningTime() {
    final milliseconds = stats.totalListeningMs;

    if (milliseconds <= 0) {
      return '${stats.totalMinutes}m';
    }

    return listeningDurationLabel(milliseconds);
  }

  // Older server responses expose only rankings. The plus sign makes their
  // lower bound explicit until complete period counts become available.
  String _distinctCount(int total, int rankingSize) => total > 0 || rankingSize == 0 ? '$total' : '$rankingSize+';

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final values = <({String label, String value})>[
      (label: 'TOTAL PLAYTIME', value: _listeningTime()),
      (label: 'TOTAL PLAYS', value: '${stats.totalPlays}'),
      (label: 'TRACKS LISTENED', value: _distinctCount(stats.uniqueTracks, stats.topTracks.length)),
      (label: 'ARTISTS LISTENED', value: _distinctCount(stats.uniqueArtists, stats.topArtists.length)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final columns = isCompact ? 2 : 4;
        final gap = s(isCompact ? 12 : 16);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: _KpiCard(
                  label: value.label,
                  value: value.value,
                  compact: isCompact,
                  tooltip: _tooltip(value.label),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  final String? tooltip;

  const _KpiCard({required this.label, required this.value, this.compact = false, this.tooltip});

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final padding = compact ? EdgeInsets.all(s(12)) : EdgeInsets.all(s(18));
    final labelSize = compact ? s(10) : s(12);
    final valueSize = compact ? s(32) : s(48);

    final surface = ObsidianGlassSurface(
      grouped: true,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                letterSpacing: s(1.4),
                color: ObsidianPalette.textMuted,
              ),
            ),
            SizedBox(height: s(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.rajdhani(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w700,
                  color: ObsidianPalette.gold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return tooltip == null ? surface : Tooltip(message: tooltip!, child: surface);
  }
}
