import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/responsive_breakpoints.dart';

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
    final isCompact = isCompactListWidth(context);
    return ObsidianHoverRow(
      onTap: onTap,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: isCompact ? 28 : 32,
            child: Center(
              child: Icon(
                searchResultIconForKind(result.kind),
                size: isCompact ? 20 : 24,
                color: ObsidianPalette.gold,
              ),
            ),
          ),
          SizedBox(width: isCompact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: isCompact ? 14.5 : null,
                    letterSpacing: isCompact ? 0.2 : 0.6,
                  ),
                ),
                if (result.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: isCompact ? 12 : null,
                      letterSpacing: isCompact ? 0 : null,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: isCompact ? 22 : 24,
            color: Colors.white38,
          ),
        ],
      ),
    );
  }
}
