import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_card.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_row_tile.dart';
import 'package:phonolite_app/ui/structures/collections/collection_sliver.dart';
import 'package:phonolite_app/ui/structures/collections/viewport_item.dart';

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
  final void Function(T, bool)? onVisibilityChanged;
  final Object? visibilityScope;

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
    this.onVisibilityChanged,
    this.visibilityScope,
  });

  @override
  Widget build(BuildContext context) => CollectionSliver<T>(
    items: items,
    isListView: isListView,
    itemBuilder: (context, item, listView) {
      final visibilityChanged = onVisibilityChanged;
      if (visibilityChanged == null) {
        return _tile(context, item, listView, true);
      }
      return ViewportItem(
        key: ValueKey((visibilityScope, artistFor(item).id)),
        onVisibilityChanged: (visible) => visibilityChanged(item, visible),
        builder: (context, visible) => _tile(context, item, listView, visible),
      );
    },
  );

  Widget _tile(BuildContext context, T item, bool listView, bool visible) {
    final artist = artistFor(item);
    final coverUrl = visible ? coverFor(item) : null;
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
  }
}
