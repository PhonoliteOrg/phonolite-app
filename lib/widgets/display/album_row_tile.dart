import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import 'album_art.dart';
import 'album_labels.dart';

class AlbumRowTile extends StatelessWidget {
  const AlbumRowTile({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    this.onTap,
    this.onLongPress,
    this.subtitle,
    this.trailing,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  final Album album;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;
  final Widget? trailing;
  final bool selectionMode;
  final bool selected;
  final bool selectable;
  final bool isDeleting;
  final VoidCallback? onSelectionToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailText = subtitle ?? albumDetailLabel(album);
    final canInteract = selectable && !isDeleting;
    final effectiveOnTap = selectionMode
        ? canInteract
              ? onSelectionToggle
              : null
        : isDeleting
        ? null
        : onTap;
    return ObsidianHoverRow(
      onTap: effectiveOnTap,
      onLongPress: selectionMode || isDeleting ? null : onLongPress,
      isActive: selectionMode && selected,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isDeleting ? 0.45 : 1,
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: canInteract && onSelectionToggle != null
                    ? (_) => onSelectionToggle!()
                    : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: const BorderSide(color: ObsidianPalette.border),
                activeColor: ObsidianPalette.gold,
              ),
              const SizedBox(width: 10),
            ],
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
                  if (detailText.isNotEmpty)
                    Text(
                      detailText,
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
            if (isDeleting)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (trailing != null)
              trailing!
            else if (!selectionMode)
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
