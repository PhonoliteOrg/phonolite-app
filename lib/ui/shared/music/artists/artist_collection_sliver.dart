import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/structures/collections/collection_sliver.dart';

/// Artist presentation for server and local collections with the same layout.
class ArtistCollectionSliver<T> extends StatelessWidget {
  final List<T> items;
  final bool isListView;
  final Artist Function(T) artistFor;
  final String? Function(T) coverFor;
  final ValueChanged<T> onOpen;
  final Map<String, String> headers;
  final bool selectionMode;
  final bool Function(T)? selected;
  final bool Function(T)? selectable;
  final bool Function(T)? isDeleting;
  final ValueChanged<T>? onSelectionToggle;

  const ArtistCollectionSliver({
    super.key,
    required this.items,
    required this.isListView,
    required this.artistFor,
    required this.coverFor,
    required this.onOpen,
    this.headers = const {},
    this.selectionMode = false,
    this.selected,
    this.selectable,
    this.isDeleting,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) => CollectionSliver<T>(
    items: items,
    isListView: isListView,
    itemBuilder: (context, item, listView) {
      final artist = artistFor(item);
      final coverUrl = coverFor(item);
      final deleting = isDeleting?.call(item) ?? false;
      final canSelect = selectable?.call(item) ?? true;
      final isSelected = selected?.call(item) ?? false;
      final toggle = onSelectionToggle;

      if (listView) {
        return ArtistRowTile(
          artist: artist,
          coverUrl: coverUrl,
          headers: headers,
          onTap: () => onOpen(item),
          selectionMode: selectionMode,
          selectable: canSelect,
          isDeleting: deleting,
          selected: isSelected,
          onSelectionToggle: toggle == null ? null : () => toggle(item),
        );
      }

      return ArtistCard(
        artist: artist,
        coverUrl: coverUrl,
        headers: headers,
        onTap: () => onOpen(item),
        selectionMode: selectionMode,
        selectable: canSelect,
        isDeleting: deleting,
        selected: isSelected,
        onSelectionToggle: toggle == null ? null : () => toggle(item),
      );
    },
  );
}
