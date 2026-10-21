import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_scale.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

double statsScaled(BuildContext context, double value) => value * ObsidianScale.of(context);

String listeningDurationLabel(int milliseconds) {
  if (milliseconds <= 0) {
    return '0m';
  }

  if (milliseconds < 1000) {
    return '<1s';
  }

  final seconds = milliseconds ~/ 1000;

  if (seconds < 60) {
    return '${seconds}s';
  }

  if (seconds >= 3600) {
    return '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m ${seconds % 60}s';
  }

  return '${seconds ~/ 60}m ${seconds % 60}s';
}

class StatsEmptyText extends StatelessWidget {
  final String text;

  const StatsEmptyText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: statsScaled(context, 12)),
    child: Text(text, style: GoogleFonts.poppins(color: ObsidianPalette.textMuted)),
  );
}
