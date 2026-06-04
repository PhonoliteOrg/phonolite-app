import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../entities/offline_library_views.dart';
import '../widgets/display/album_card.dart';
import '../widgets/display/album_row_tile.dart';
import '../widgets/display/artist_hero.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/layout/safe_sliver_grid.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/collection_view_toggle_button.dart';
import '../widgets/ui/obsidian_widgets.dart';
import 'local_album_detail_screen.dart';

class LocalArtistDetailScreen extends StatefulWidget {
  const LocalArtistDetailScreen({super.key, required this.group});

  final OfflineArtistGroup group;

  @override
  State<LocalArtistDetailScreen> createState() =>
      _LocalArtistDetailScreenState();
}

class _LocalArtistDetailScreenState extends State<LocalArtistDetailScreen> {
  bool _albumSelectionMode = false;
  final Set<String> _selectedAlbumIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: StreamBuilder<List<OfflineTrackDownload>>(
          stream: controller.offlineDownloadsStream,
          initialData: controller.offlineDownloads,
          builder: (context, _) {
            final group = _currentGroup(controller);
            final removableAlbumIds = _removableAlbumIds(group.albums);
            final selectedAlbums = _selectedAlbums(
              group.albums,
              removableAlbumIds,
            );
            final removingTrackIds = _removingTrackIds(controller);
            return StreamBuilder<bool>(
              stream: controller.collectionListModeStream,
              initialData: controller.collectionListMode,
              builder: (context, viewModeSnapshot) {
                final showCollectionList =
                    viewModeSnapshot.data ?? controller.collectionListMode;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          width: double.infinity,
                          child: Row(
                            children: [
                              CommandLinkButton(
                                label: 'Back to library',
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              const Spacer(),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: _albumSelectionMode
                                    ? [
                                        DownloadSelectionToolbar(
                                          selectedCount: selectedAlbums.length,
                                          totalCount: removableAlbumIds.length,
                                          onCancel: _clearAlbumSelection,
                                          onSelectAll: () => _selectAllAlbums(
                                            removableAlbumIds,
                                          ),
                                          onDeselectAll: _deselectAllAlbums,
                                          onRemove: selectedAlbums.isEmpty
                                              ? null
                                              : () =>
                                                    _removeSelectedAlbumDownloads(
                                                      controller,
                                                      selectedAlbums,
                                                    ),
                                        ),
                                      ]
                                    : [
                                        _editAlbumSelectionButton(
                                          removableAlbumIds.isNotEmpty
                                              ? _startAlbumSelection
                                              : null,
                                        ),
                                        CollectionViewToggleButton(
                                          isListView: showCollectionList,
                                          onPressed: controller
                                              .toggleCollectionListMode,
                                        ),
                                      ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverToBoxAdapter(
                        child: ArtistHero(
                          artist: group.toArtist(),
                          coverUrl: group.coverPath,
                          bannerUrl: group.bannerPath,
                          headers: const {},
                        ),
                      ),
                    ),
                    if (group.albums.isEmpty)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: EmptyState(
                            title: 'No downloaded albums',
                            message:
                                'Downloaded albums for this artist appear here.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        sliver: showCollectionList
                            ? SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  if (index.isOdd) {
                                    return const Divider(height: 1);
                                  }
                                  final album = group.albums[index ~/ 2];
                                  final isDeleting = _albumHasRemovingTracks(
                                    album,
                                    removingTrackIds,
                                  );
                                  return AlbumRowTile(
                                    album: album.toAlbum(),
                                    coverUrl: album.coverPath ?? '',
                                    headers: const {},
                                    onTap: () => _openAlbum(context, album),
                                    selectionMode: _albumSelectionMode,
                                    selectable:
                                        !isDeleting &&
                                        removableAlbumIds.contains(
                                          _albumSelectionKey(album),
                                        ),
                                    isDeleting: isDeleting,
                                    selected: _selectedAlbumIds.contains(
                                      _albumSelectionKey(album),
                                    ),
                                    onSelectionToggle: () =>
                                        _toggleAlbumSelection(album),
                                  );
                                }, childCount: group.albums.length * 2 - 1),
                              )
                            : SafeSliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 240,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: 0.82,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final album = group.albums[index];
                                  final isDeleting = _albumHasRemovingTracks(
                                    album,
                                    removingTrackIds,
                                  );
                                  return AlbumCard(
                                    album: album.toAlbum(),
                                    coverUrl: album.coverPath ?? '',
                                    headers: const {},
                                    onTap: () => _openAlbum(context, album),
                                    selectionMode: _albumSelectionMode,
                                    selectable:
                                        !isDeleting &&
                                        removableAlbumIds.contains(
                                          _albumSelectionKey(album),
                                        ),
                                    isDeleting: isDeleting,
                                    selected: _selectedAlbumIds.contains(
                                      _albumSelectionKey(album),
                                    ),
                                    onSelectionToggle: () =>
                                        _toggleAlbumSelection(album),
                                  );
                                }, childCount: group.albums.length),
                              ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _openAlbum(BuildContext context, OfflineAlbumGroup album) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LocalAlbumDetailScreen(album: album)),
    );
  }

  OfflineArtistGroup _currentGroup(AppController controller) {
    final groups = offlineArtistGroups(controller.offlineTracks);
    for (final group in groups) {
      if (group.id == widget.group.id) {
        return group;
      }
    }
    return OfflineArtistGroup(
      id: widget.group.id,
      name: widget.group.name,
      albums: const <OfflineAlbumGroup>[],
      coverPath: widget.group.coverPath,
      bannerPath: widget.group.bannerPath,
    );
  }

  Future<void> _removeSelectedAlbumDownloads(
    AppController controller,
    List<OfflineAlbumGroup> albums,
  ) async {
    final tracks = <Track>[for (final album in albums) ...album.tracks];
    if (tracks.isEmpty) {
      return;
    }
    final label = albums.length == 1
        ? albums.single.title
        : '${albums.length} albums';
    final confirmed = await confirmRemoveDownloadedTracks(
      context,
      tracks,
      label: label,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await controller.removeDownloadedTracks(
      tracks,
      label: label,
      scope: OfflineDeletionScope.album(
        id: albums.length == 1 ? albums.single.id : null,
        label: label,
      ),
    );
    if (mounted) {
      _clearAlbumSelection();
    }
  }

  Set<String> _removableAlbumIds(List<OfflineAlbumGroup> albums) {
    return <String>{
      for (final album in albums)
        if (album.tracks.isNotEmpty) _albumSelectionKey(album),
    };
  }

  List<OfflineAlbumGroup> _selectedAlbums(
    List<OfflineAlbumGroup> albums,
    Set<String> removableIds,
  ) {
    return albums
        .where((album) {
          final key = _albumSelectionKey(album);
          return removableIds.contains(key) && _selectedAlbumIds.contains(key);
        })
        .toList(growable: false);
  }

  void _toggleAlbumSelection(OfflineAlbumGroup album) {
    final key = _albumSelectionKey(album);
    setState(() {
      _albumSelectionMode = true;
      if (!_selectedAlbumIds.remove(key)) {
        _selectedAlbumIds.add(key);
      }
    });
  }

  void _selectAllAlbums(Set<String> albumIds) {
    setState(() {
      _albumSelectionMode = true;
      _selectedAlbumIds
        ..clear()
        ..addAll(albumIds);
    });
  }

  void _deselectAllAlbums() {
    setState(() {
      _albumSelectionMode = true;
      _selectedAlbumIds.clear();
    });
  }

  void _startAlbumSelection() {
    setState(() {
      _albumSelectionMode = true;
      _selectedAlbumIds.clear();
    });
  }

  void _clearAlbumSelection() {
    setState(() {
      _albumSelectionMode = false;
      _selectedAlbumIds.clear();
    });
  }

  Widget _editAlbumSelectionButton(VoidCallback? onPressed) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(
        icon: Icons.edit_rounded,
        onPressed: onPressed,
      ),
    );
  }

  String _albumSelectionKey(OfflineAlbumGroup album) => album.id;

  Set<String> _removingTrackIds(AppController controller) {
    final ids = <String>{};
    for (final download in controller.offlineDownloads) {
      if (download.status != OfflineDownloadStatus.removing) {
        continue;
      }
      _addTrackIdentityKeys(ids, download.track);
      final localTrackId = download.localTrackId?.trim();
      if (localTrackId != null && localTrackId.isNotEmpty) {
        ids.add(localTrackId);
      }
    }
    return ids;
  }

  bool _albumHasRemovingTracks(
    OfflineAlbumGroup album,
    Set<String> removingTrackIds,
  ) {
    if (removingTrackIds.isEmpty) {
      return false;
    }
    return album.tracks.any(
      (track) => _trackMatchesAnyIdentity(track, removingTrackIds),
    );
  }

  bool _trackMatchesAnyIdentity(Track track, Set<String> ids) {
    final trackIds = <String>{};
    _addTrackIdentityKeys(trackIds, track);
    return trackIds.any(ids.contains);
  }

  void _addTrackIdentityKeys(Set<String> target, Track track) {
    for (final value in <String?>[
      track.id,
      track.localId,
      track.serverTrackId,
    ]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        target.add(trimmed);
      }
    }
  }
}
