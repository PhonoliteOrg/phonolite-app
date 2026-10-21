import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_report.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_module_shell.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';

class StatsTopArtistsSection extends StatelessWidget {
  final List<StatsItem> artists;
  final String? Function(StatsItem)? coverUrl;
  final Map<String, String> headers;
  final ValueChanged<StatsItem>? onArtistTap;

  const StatsTopArtistsSection({
    super.key,
    required this.artists,
    required this.coverUrl,
    required this.headers,
    required this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double value) => statsScaled(context, value);

    final topArtists = artists.take(5).toList();

    return StatsModuleShell(
      title: 'TOP ARTISTS',
      child: Column(
        children: [
          if (topArtists.isEmpty)
            StatsEmptyText('No artists yet.')
          else
            for (var i = 0; i < topArtists.length; i++)
              ArtistRowTile(
                key: topArtists[i].id.trim().isEmpty ? null : ValueKey('stats-artist-${topArtists[i].id}'),
                onTap: onArtistTap == null || topArtists[i].id.trim().isEmpty
                    ? null
                    : () => onArtistTap!(topArtists[i]),
                artist: Artist(id: topArtists[i].id, name: topArtists[i].name, albumCount: 0),
                coverUrl: coverUrl?.call(topArtists[i]),
                headers: headers,
                subtitle: '${listeningDurationLabel(topArtists[i].listeningMs)} listened',
                trailing: SizedBox(
                  width: s(30),
                  child: Text(
                    '${i + 1}'.padLeft(2, '0'),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.rajdhani(
                      fontSize: s(18),
                      fontWeight: FontWeight.w700,
                      color: ObsidianPalette.gold,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
