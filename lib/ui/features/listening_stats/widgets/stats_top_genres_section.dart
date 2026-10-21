import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_module_shell.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/formatting/genre_text.dart';

class StatsTopGenresSection extends StatelessWidget {
  final List<StatsItem> genres;
  final int totalListeningMs;
  final int otherListeningMs;
  final int unclassifiedListeningMs;
  final bool fillHeight;

  const StatsTopGenresSection({
    super.key,
    required this.genres,
    required this.totalListeningMs,
    required this.otherListeningMs,
    required this.unclassifiedListeningMs,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    return StatsModuleShell(
      title: 'TOP GENRES',
      expandChild: fillHeight,
      tooltip:
          'Listening time is shared evenly between a song’s genres. '
          'Other genres includes those outside the top five. '
          'Unclassified means genre metadata is unavailable. '
          'Displayed durations are rounded down to whole seconds.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (genres.isEmpty && otherListeningMs == 0 && unclassifiedListeningMs == 0)
            StatsEmptyText('No genres yet.')
          else
            for (final genre in genres)
              _GenreBar(label: genre.name, listeningMs: genre.listeningMs, totalListeningMs: totalListeningMs),
          if (otherListeningMs > 0)
            _GenreBar(label: 'Other genres', listeningMs: otherListeningMs, totalListeningMs: totalListeningMs),
          if (unclassifiedListeningMs > 0)
            _GenreBar(label: 'Unclassified', listeningMs: unclassifiedListeningMs, totalListeningMs: totalListeningMs),
        ],
      ),
    );
  }
}

class _GenreBar extends StatelessWidget {
  final String label;
  final int listeningMs;
  final int totalListeningMs;

  const _GenreBar({required this.label, required this.listeningMs, required this.totalListeningMs});

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final percent = totalListeningMs <= 0 ? 0.0 : listeningMs / totalListeningMs;
    final barPercent = percent.clamp(0.0, 1.0);
    final timeLabel = listeningDurationLabel(listeningMs);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: s(10)),
      child: Row(
        children: [
          SizedBox(
            width: s(100),
            child: Text(
              genreDisplayLabel(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: s(1.0)),
            ),
          ),
          SizedBox(width: s(12)),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: s(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withByteOpacity(0.05),
                    borderRadius: BorderRadius.circular(s(6)),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: barPercent,
                  child: Container(
                    height: s(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ObsidianPalette.gold, ObsidianPalette.gold.withByteOpacity(0.4)],
                      ),
                      borderRadius: BorderRadius.circular(s(6)),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: s(1),
                  child: Container(width: s(2), height: s(6), color: Colors.white.withByteOpacity(0.8)),
                ),
              ],
            ),
          ),
          SizedBox(width: s(12)),
          Text(
            timeLabel,
            style: GoogleFonts.rajdhani(
              fontSize: s(12),
              fontWeight: FontWeight.w700,
              color: ObsidianPalette.gold,
              letterSpacing: s(1.1),
            ),
          ),
        ],
      ),
    );
  }
}
