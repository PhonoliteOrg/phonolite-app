import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/dismissible_selection_area.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';
import 'package:phonolite_app/ui/shared/music/compact_hero_details.dart';

/// Shared disclosure content and selection treatment for compact music heroes.
class MediaHeroDetails extends StatelessWidget {
  final String label;
  final String genres;
  final String? summary;

  const MediaHeroDetails({super.key, required this.label, required this.genres, this.summary});

  @override
  Widget build(BuildContext context) {
    final hasSummary = summary != null && summary!.isNotEmpty;

    if (genres.isEmpty && !hasSummary) {
      return const SizedBox.shrink();
    }

    return CompactHeroDetails(
      label: label,
      child: DefaultSelectionStyle(
        selectionColor: accentGold.withValues(alpha: 0.35),
        child: DismissibleSelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (genres.isNotEmpty)
                Text(genres, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11, height: 1.4)),
              if (genres.isNotEmpty && hasSummary) const SizedBox(height: 8),
              if (hasSummary)
                Text(summary!, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
