import 'package:flutter/material.dart';

import '../../entities/models.dart';
import '../layout/safe_sliver_grid.dart';
import 'album_card.dart';
import 'album_row_tile.dart';

class ArtistReleaseHeading extends StatelessWidget {
  const ArtistReleaseHeading({
    super.key,
    required this.title,
    required this.count,
  });
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    sliver: SliverToBoxAdapter(
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
  );
}

/// Related releases use the same album cards and rows as the main collection.
class ArtistContributionSliver extends StatelessWidget {
  const ArtistContributionSliver({
    super.key,
    required this.title,
    required this.entries,
    required this.isListView,
    required this.coverFor,
    required this.onOpen,
    this.headers = const {},
    this.selectionMode = false,
    this.selected,
    this.selectable,
    this.isDeleting,
    this.onSelectionToggle,
  });
  final String title;
  final List<ArtistReleaseContribution> entries;
  final bool isListView;
  final String Function(Album) coverFor;
  final void Function(Album) onOpen;
  final Map<String, String> headers;
  final bool selectionMode;
  final bool Function(ArtistReleaseContribution)? selected;
  final bool Function(ArtistReleaseContribution)? selectable;
  final bool Function(ArtistReleaseContribution)? isDeleting;
  final void Function(ArtistReleaseContribution)? onSelectionToggle;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      ArtistReleaseHeading(title: title, count: entries.length),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        sliver: isListView
            ? SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index.isOdd) return const Divider(height: 1);
                  return _buildAlbum(context, index ~/ 2);
                }, childCount: entries.isEmpty ? 0 : entries.length * 2 - 1),
              )
            : SafeSliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  _buildAlbum,
                  childCount: entries.length,
                ),
              ),
      ),
    ],
  );

  Widget _buildAlbum(BuildContext context, int index) {
    final entry = entries[index];
    final coverUrl = coverFor(entry.album);
    final isSelected = selected?.call(entry) ?? false;
    final canSelect = selectable?.call(entry) ?? true;
    final deleting = isDeleting?.call(entry) ?? false;
    final toggleSelection = onSelectionToggle == null
        ? null
        : () => onSelectionToggle!(entry);
    if (isListView) {
      return AlbumRowTile(
        album: entry.album,
        coverUrl: coverUrl,
        headers: headers,
        onTap: () => onOpen(entry.album),
        selectionMode: selectionMode,
        selected: isSelected,
        selectable: canSelect,
        isDeleting: deleting,
        onSelectionToggle: toggleSelection,
      );
    }
    return AlbumCard(
      album: entry.album,
      coverUrl: coverUrl,
      headers: headers,
      onTap: () => onOpen(entry.album),
      selectionMode: selectionMode,
      selected: isSelected,
      selectable: canSelect,
      isDeleting: deleting,
      onSelectionToggle: toggleSelection,
    );
  }
}
