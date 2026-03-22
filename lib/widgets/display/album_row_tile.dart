import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import 'album_art.dart';

class AlbumRowTile extends StatelessWidget {
  const AlbumRowTile({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    required this.onTap,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      onTap: onTap,
      child: Row(
        children: [
          AlbumArt(
            title: album.title,
            size: 52,
            imageUrl: coverUrl,
            headers: headers,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailLine(album),
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

  String _detailLine(Album album) {
    final details = <String>[];
    if (album.year != null) {
      details.add(album.year.toString());
    }
    details.add(
      album.trackCount == 1 ? '1 track' : '${album.trackCount} tracks',
    );
    final genres = album.genres
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .take(2);
    if (genres.isNotEmpty) {
      details.add(genres.join(', '));
    }
    return details.join(' / ');
  }
}
