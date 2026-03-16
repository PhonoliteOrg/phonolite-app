import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';

IconData searchResultIconForKind(String kind) {
  switch (kind) {
    case 'artist':
      return Icons.person_rounded;
    case 'album':
      return Icons.album_rounded;
    case 'track':
      return Icons.music_note_rounded;
    default:
      return Icons.search_rounded;
  }
}

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ObsidianHoverRow(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: Icon(
                searchResultIconForKind(result.kind),
                color: ObsidianPalette.gold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.6,
                  ),
                ),
                if (result.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
    );
  }
}
