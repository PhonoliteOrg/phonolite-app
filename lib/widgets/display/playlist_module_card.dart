import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../entities/models.dart';
import '../ui/chamfer_clipper.dart';
import '../ui/obsidian_theme.dart';

class PlaylistModuleCard extends StatefulWidget {
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
  State<PlaylistModuleCard> createState() => _PlaylistModuleCardState();
}

class _PlaylistModuleCardState extends State<PlaylistModuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final barColor =
        _hovered ? ObsidianPalette.gold : Colors.white.withOpacity(0.1);
    final glow = _hovered
        ? [
            BoxShadow(
              color: ObsidianPalette.gold.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_hovered ? 5 : 0, 0, 0),
        child: ClipPath(
          clipper: const ChamferClipper(cutSize: 15),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: Container(
                height: 80,
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
                            widget.playlist.name.toUpperCase(),
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
      ),
    );
  }
}
