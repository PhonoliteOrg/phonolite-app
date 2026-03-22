import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import 'artist_avatar.dart';

class ArtistRowTile extends StatelessWidget {
  const ArtistRowTile({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
  });

  final Artist artist;
  final String? coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      onTap: onTap,
      child: Row(
        children: [
          ArtistAvatar(
            name: artist.name,
            size: 48,
            imageUrl: coverUrl,
            headers: headers,
            fit: BoxFit.contain,
            paddingFraction: 0,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailLine(artist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ObsidianPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }

  String _detailLine(Artist artist) {
    final details = <String>[
      artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums',
    ];
    final genres = artist.genres
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .take(2);
    if (genres.isNotEmpty) {
      details.add(genres.join(', '));
    }
    return details.join(' / ');
  }
}
