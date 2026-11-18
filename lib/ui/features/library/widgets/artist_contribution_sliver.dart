import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/ui/features/library/widgets/artist_release_heading.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_collection_sliver.dart';

/// Related releases use the same album cards and rows as the main collection.
class ArtistContributionSliver extends StatelessWidget {
  final String title;
  final List<ArtistReleaseContribution> entries;
  final bool isListView;
  final String Function(Album) coverFor;
  final void Function(Album) onOpen;
  final bool selectionMode;
  final bool Function(ArtistReleaseContribution)? selected;
  final bool Function(ArtistReleaseContribution)? selectable;
  final bool Function(ArtistReleaseContribution)? isDeleting;
  final void Function(ArtistReleaseContribution)? onSelectionToggle;

  const ArtistContributionSliver({
    super.key,
    required this.title,
    required this.entries,
    required this.isListView,
    required this.coverFor,
    required this.onOpen,
    this.selectionMode = false,
    this.selected,
    this.selectable,
    this.isDeleting,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      ArtistReleaseHeading(title: title, count: entries.length),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        sliver: AlbumCollectionSliver<ArtistReleaseContribution>(
          items: entries,
          isListView: isListView,
          albumFor: (entry) => entry.album,
          coverFor: (entry) => coverFor(entry.album),
          onOpen: (entry) => onOpen(entry.album),
          selectionMode: selectionMode,
          selected: selected,
          selectable: selectable,
          isDeleting: isDeleting,
          onSelectionToggle: onSelectionToggle,
        ),
      ),
    ],
  );
}
