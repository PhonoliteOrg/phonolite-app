import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_card.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_row_tile.dart';
import 'package:phonolite_app/ui/structures/collections/collection_sliver.dart';
import 'package:phonolite_app/ui/structures/sections/base_sliver_section.dart';

class PlaylistSection extends BaseSliverSection {
  final String? title;
  final List<Playlist> playlists;
  final bool showListView;
  final Map<String, String> headers;
  final String? Function(Playlist playlist) coverUrlFor;
  final ValueChanged<Playlist> onOpen;
  final ValueChanged<Playlist> onPlayFromTop;
  final bool selectionMode;
  final bool Function(Playlist playlist) isSelected;
  final bool Function(Playlist playlist) isDeleting;
  final ValueChanged<Playlist> onSelectionToggle;
  final String emptyText;

  const PlaylistSection({
    super.key,
    required this.title,
    required this.playlists,
    required this.showListView,
    required this.headers,
    required this.coverUrlFor,
    required this.onOpen,
    required this.onPlayFromTop,
    required this.selectionMode,
    required this.isSelected,
    required this.isDeleting,
    required this.onSelectionToggle,
    required this.emptyText,
  });

  @override
  String? get sectionTitle => title;

  @override
  Widget sectionSliver(BuildContext context) {
    return playlists.isEmpty
        ? SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                emptyText,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 0.6),
              ),
            ),
          )
        : CollectionSliver<Playlist>(
            items: playlists,
            isListView: showListView,
            itemBuilder: (context, playlist, listView) {
              final album = _playlistAlbum(playlist);
              final coverUrl = coverUrlFor(playlist) ?? '';

              void open() => onOpen(playlist);

              final play = playlist.trackIds.isEmpty ? null : () => onPlayFromTop(playlist);
              final selected = isSelected(playlist);
              final deleting = isDeleting(playlist);

              void toggle() => onSelectionToggle(playlist);

              return listView
                  ? AlbumRowTile(
                      album: album,
                      coverUrl: coverUrl,
                      headers: headers,
                      onTap: open,
                      onLongPress: play,
                      selectionMode: selectionMode,
                      selected: selected,
                      isDeleting: deleting,
                      onSelectionToggle: toggle,
                    )
                  : AlbumCard(
                      album: album,
                      coverUrl: coverUrl,
                      headers: headers,
                      onTap: open,
                      onLongPress: play,
                      selectionMode: selectionMode,
                      selected: selected,
                      isDeleting: deleting,
                      onSelectionToggle: toggle,
                    );
            },
          );
  }

  Album _playlistAlbum(Playlist playlist) {
    return Album(
      id: playlist.id,
      title: playlist.name,
      artist: 'Playlist',
      artistId: '',
      trackCount: playlist.totalTrackCount,
    );
  }
}
