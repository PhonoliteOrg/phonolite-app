import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artist_avatar.dart';
import 'package:phonolite_app/ui/shared/music/media_selection.dart';
import 'package:phonolite_app/ui/shared/music/selectable_media_row.dart';

class ArtistRowTile extends StatelessWidget {
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

  const ArtistRowTile({
    super.key,
    required this.artist,
    required this.coverUrl,
    required this.headers,
    this.subtitle,
    this.trailing,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.isDeleting = false,
    this.onTap,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = isCompactListWidth(context);

    return SelectableMediaRow(
      title: artist.name,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
      selection: MediaSelection(
        selectionMode: selectionMode,
        selected: selected,
        selectable: selectable,
        isDeleting: isDeleting,
        onSelectionToggle: onSelectionToggle,
      ),
      artwork: ArtistAvatar(
        name: artist.name,
        size: isCompact ? 42 : 48,
        imageUrl: coverUrl,
        headers: headers,
        fit: BoxFit.contain,
        paddingFraction: 0,
      ),
    );
  }
}
