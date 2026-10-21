import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';
import 'package:phonolite_app/ui/shared/music/selectable_media_row.dart';

class AlbumRowTile extends StatelessWidget {
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

  const AlbumRowTile({
    super.key,
    required this.album,
    required this.coverUrl,
    required this.headers,
    this.subtitle,
    this.trailing,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onTap,
    this.onLongPress,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = isCompactListWidth(context);

    return SelectableMediaRow(
      title: album.title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
      selection: MediaSelection(
        selectionMode: selectionMode,
        selected: selected,
        selectable: selectable,
        isDeleting: isDeleting,
        onSelectionToggle: onSelectionToggle,
      ),
      artwork: AlbumArt(title: album.title, size: isCompact ? 44 : 52, imageUrl: coverUrl, headers: headers),
    );
  }
}
