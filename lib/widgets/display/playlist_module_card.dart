import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/models.dart';
import '../ui/hoverable.dart';
import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

class PlaylistModuleCard extends StatelessWidget {
  const PlaylistModuleCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onLongPress,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ObsidianHoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final barColor =
            hovered ? ObsidianPalette.gold : Colors.white.withOpacity(0.1);
        final glow = hovered
            ? [
                BoxShadow(
                  color: ObsidianPalette.gold.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : const <BoxShadow>[];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(hovered ? 5 : 0, 0, 0),
          child: ObsidianChamferPanel(
            cut: 15,
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.04),
                  Colors.white.withOpacity(0.01),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: SizedBox(
                  height: 80,
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: barColor,
                          boxShadow: glow,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              playlist.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.rajdhani(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
