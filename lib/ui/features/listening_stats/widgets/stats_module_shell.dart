import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/surfaces/obsidian_glass_surface.dart';

class StatsModuleShell extends StatelessWidget {
  final String title;
  final Widget child;
  final String? tooltip;
  final bool expandChild;

  const StatsModuleShell({super.key, required this.title, required this.child, this.tooltip, this.expandChild = false});

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    return ObsidianGlassSurface(
      grouped: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(s(18), s(16), s(18), s(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: tooltip ?? '',
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.rajdhani(fontSize: s(14), fontWeight: FontWeight.w700, letterSpacing: s(1.6)),
              ),
            ),
            SizedBox(height: s(12)),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
