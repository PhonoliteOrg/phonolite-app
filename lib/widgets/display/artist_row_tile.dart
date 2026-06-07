import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../ui/hover_row.dart';
import '../ui/obsidian_theme.dart';
import '../ui/responsive_breakpoints.dart';
import 'album_labels.dart';
import 'artist_avatar.dart';

class ArtistRowTile extends StatelessWidget {
  const ArtistRowTile({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.headers,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onSelectionToggle,
  });

  final Artist artist;
  final String? coverUrl;
  final Map<String, String> headers;
  final VoidCallback? onTap;
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
    final isCompact = isCompactListWidth(context);
    final detailText = subtitle ?? artistDetailLabel(artist);
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
      isActive: selectionMode && selected,
      padding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              SizedBox(width: isCompact ? 8 : 10),
            ],
            ArtistAvatar(
              name: artist.name,
              size: isCompact ? 42 : 48,
              imageUrl: coverUrl,
              headers: headers,
              fit: BoxFit.contain,
              paddingFraction: 0,
            ),
            SizedBox(width: isCompact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: isCompact ? 14.5 : null,
                      letterSpacing: isCompact ? 0.2 : 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (detailText.isNotEmpty)
                    Text(
                      detailText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: isCompact ? 12 : null,
                        letterSpacing: isCompact ? 0 : null,
                        color: ObsidianPalette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: isCompact ? 8 : 12),
            if (isDeleting)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (trailing != null)
              trailing!
            else if (!selectionMode)
              Icon(
                Icons.chevron_right_rounded,
                size: isCompact ? 22 : 24,
                color: Colors.white38,
              ),
          ],
        ),
      ),
    );
  }
}
