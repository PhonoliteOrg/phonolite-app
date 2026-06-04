import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../entities/offline_download_manager.dart';
import '../entities/offline_library.dart';
import '../entities/offline_library_views.dart';
import '../widgets/display/artist_card.dart';
import '../widgets/display/artist_row_tile.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/inputs/search_hud.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layout/safe_sliver_grid.dart';
import '../widgets/layout/search_results_sliver.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/modals/download_manager_panel.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/ui/obsidian_widgets.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'local_artist_detail_screen.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  Timer? _searchDebounce;
  bool _requestedServerLoad = false;
  bool _artistSelectionMode = false;
  bool _refreshingLibrary = false;
  final Set<String> _selectedArtistIds = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleArtistScroll);
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_handleArtistScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (!controller.authState.isAuthorized) {
      _requestedServerLoad = false;
      return;
    }
    if (controller.artists.isEmpty) {
      _requestedServerLoad = true;
      unawaited(controller.loadArtists());
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadMoreArtists(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, snapshot) {
        final authState = snapshot.data ?? controller.authState;
        if (!authState.isAuthorized) {
          _requestedServerLoad = false;
          return _buildOfflineLibrary(controller);
        }
        return _buildServerLibrary(controller);
      },
    );
  }

  Widget _buildServerLibrary(AppController controller) {
    if (!_requestedServerLoad && controller.artists.isEmpty) {
      _requestedServerLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.authState.isAuthorized) {
          unawaited(controller.loadArtists());
        }
      });
    }
    final authHeadersMap = authHeaders(controller);

    return Container(
      color: bgDark,
      child: StreamBuilder<List<SearchResult>>(
        stream: controller.searchStream,
        initialData: controller.searchResults,
        builder: (context, searchSnapshot) {
          final results = searchSnapshot.data ?? [];
          return StreamBuilder<bool>(
            stream: controller.artistsLoadingStream,
            initialData: controller.artistsLoading,
            builder: (context, loadingSnapshot) {
              final isLoading = loadingSnapshot.data ?? false;
              return StreamBuilder<bool>(
                stream: controller.searchLoadingStream,
                initialData: controller.searchLoading,
                builder: (context, searchLoadingSnapshot) {
                  final isSearchLoading = searchLoadingSnapshot.data ?? false;
                  return StreamBuilder<List<Artist>>(
                    stream: controller.artistsStream,
                    initialData: controller.artists,
                    builder: (context, artistSnapshot) {
                      final artists = artistSnapshot.data ?? [];
                      final query = _searchController.text.trim();
                      if (query.isEmpty &&
                          artists.isNotEmpty &&
                          controller.hasMoreArtists &&
                          !isLoading) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _maybeLoadMoreArtists(),
                        );
                      }
                      return StreamBuilder<bool>(
                        stream: controller.collectionListModeStream,
                        initialData: controller.collectionListMode,
                        builder: (context, viewModeSnapshot) {
                          final showCollectionList =
                              viewModeSnapshot.data ??
                              controller.collectionListMode;
                          return StreamBuilder<OfflineLibrarySnapshot>(
                            stream: controller.offlineLibrarySnapshotStream,
                            initialData: controller.offlineLibrarySnapshot,
                            builder: (context, librarySnapshot) {
                              final offlineSnapshot =
                                  librarySnapshot.data ??
                                  controller.offlineLibrarySnapshot;
                              final offlineTracks = offlineSnapshot.tracks;
                              final filteredOfflineTracks =
                                  _filterOfflineTracks(offlineTracks, query);
                              final offlineGroups = query.isEmpty
                                  ? offlineSnapshot.artistGroups
                                  : offlineArtistGroups(filteredOfflineTracks);
                              final selectedGroups = _selectedOfflineArtists(
                                offlineGroups,
                              );
                              final slivers = query.isEmpty
                                  ? <Widget>[
                                      ..._downloadedMusicSlivers(
                                        controller: controller,
                                        tracks: offlineTracks,
                                        groups: offlineGroups,
                                        emptyTitle: 'No downloaded tracks',
                                        emptyMessage:
                                            'Download tracks from a connected server to keep them here.',
                                        showCollectionList: showCollectionList,
                                      ),
                                      ..._serverArtistSlivers(
                                        controller,
                                        artists: artists,
                                        authHeadersMap: authHeadersMap,
                                        showCollectionList: showCollectionList,
                                        isLoading: isLoading,
                                      ),
                                    ]
                                  : <Widget>[
                                      if (filteredOfflineTracks.isNotEmpty)
                                        ..._downloadedMusicSlivers(
                                          controller: controller,
                                          tracks: filteredOfflineTracks,
                                          groups: offlineGroups,
                                          emptyTitle: 'No downloaded results',
                                          emptyMessage:
                                              'Try a different downloaded track search.',
                                          showCollectionList:
                                              showCollectionList,
                                          showEmpty: false,
                                        ),
                                      ..._connectedSearchSlivers(
                                        controller,
                                        query: query,
                                        results: results,
                                        isSearchLoading: isSearchLoading,
                                        hasOfflineResults:
                                            filteredOfflineTracks.isNotEmpty,
                                      ),
                                    ];

                              return CustomScrollView(
                                controller: _scrollController,
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      16,
                                      20,
                                      12,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: LibraryHeader(
                                        moduleCount: artists.length,
                                        trailing: _artistSelectionMode
                                            ? _artistSelectionToolbar(
                                                controller: controller,
                                                groups: offlineGroups,
                                                selectedGroups: selectedGroups,
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _refreshLibraryButton(
                                                    controller,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  _downloadManagerButton(),
                                                  const SizedBox(width: 10),
                                                  _editLibraryButton(
                                                    offlineGroups.isNotEmpty
                                                        ? _startArtistSelection
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  _collectionViewButton(
                                                    isListView:
                                                        showCollectionList,
                                                    onPressed: controller
                                                        .toggleCollectionListMode,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      20,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: SearchHud(
                                        controller: _searchController,
                                        onSubmit: () => _runSearch(controller),
                                        onChanged: () =>
                                            _queueSearch(controller),
                                        onClear: () => _clearSearch(controller),
                                      ),
                                    ),
                                  ),
                                  ...slivers,
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOfflineLibrary(AppController controller) {
    return Container(
      color: bgDark,
      child: StreamBuilder<OfflineLibrarySnapshot>(
        stream: controller.offlineLibrarySnapshotStream,
        initialData: controller.offlineLibrarySnapshot,
        builder: (context, snapshot) {
          return StreamBuilder<bool>(
            stream: controller.collectionListModeStream,
            initialData: controller.collectionListMode,
            builder: (context, viewModeSnapshot) {
              final showCollectionList =
                  viewModeSnapshot.data ?? controller.collectionListMode;
              final query = _searchController.text.trim().toLowerCase();
              final offlineSnapshot =
                  snapshot.data ?? controller.offlineLibrarySnapshot;
              final tracks = offlineSnapshot.tracks;
              final filteredTracks = query.isEmpty
                  ? tracks
                  : tracks.where((track) {
                      final target =
                          '${track.title} ${track.artist} ${track.album}'
                              .toLowerCase();
                      return target.contains(query);
                    }).toList();
              final filteredGroups = query.isEmpty
                  ? offlineSnapshot.artistGroups
                  : offlineArtistGroups(filteredTracks);
              final selectedGroups = _selectedOfflineArtists(filteredGroups);

              return CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: LibraryHeader(
                        moduleCount: tracks.length,
                        trailing: _artistSelectionMode
                            ? _artistSelectionToolbar(
                                controller: controller,
                                groups: filteredGroups,
                                selectedGroups: selectedGroups,
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _refreshLibraryButton(controller),
                                  const SizedBox(width: 10),
                                  _downloadManagerButton(),
                                  const SizedBox(width: 10),
                                  _editLibraryButton(
                                    filteredGroups.isNotEmpty
                                        ? _startArtistSelection
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  _collectionViewButton(
                                    isListView: showCollectionList,
                                    onPressed:
                                        controller.toggleCollectionListMode,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: SearchHud(
                        controller: _searchController,
                        onSubmit: () => setState(() {}),
                        onChanged: () => setState(() {}),
                        onClear: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateText(
                        title: 'No downloaded tracks',
                        message:
                            'Connect to a server and download tracks to listen offline.',
                      ),
                    )
                  else if (filteredTracks.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateText(
                        title: 'No offline results',
                        message: 'Try a different downloaded track search.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: _offlineArtistCollectionSliver(
                        controller,
                        filteredGroups,
                        showCollectionList,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _downloadManagerButton({bool enabled = true}) {
    return Tooltip(
      message: 'Download Manager',
      child: ObsidianHudIconButton(
        icon: Icons.download_for_offline_rounded,
        onPressed: enabled
            ? () => unawaited(showDownloadManagerPanel(context))
            : null,
      ),
    );
  }

  Widget _editLibraryButton(VoidCallback? onPressed) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(
        icon: Icons.edit_rounded,
        onPressed: onPressed,
      ),
    );
  }

  Widget _collectionViewButton({
    required bool isListView,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: isListView ? 'Show cards' : 'Show list',
      child: Semantics(
        button: true,
        toggled: isListView,
        label: 'Library collection view',
        child: ObsidianHudIconButton(
          icon: Icons.view_agenda_rounded,
          isActive: isListView,
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _artistSelectionToolbar({
    required AppController controller,
    required List<OfflineArtistGroup> groups,
    required List<OfflineArtistGroup> selectedGroups,
  }) {
    return DownloadSelectionToolbar(
      selectedCount: selectedGroups.length,
      totalCount: groups.length,
      onCancel: _clearArtistSelection,
      onSelectAll: () => _selectAllArtists(groups.map(_artistSelectionKey)),
      onDeselectAll: _deselectAllArtists,
      onRemove: selectedGroups.isEmpty
          ? null
          : () => _removeSelectedArtistDownloads(controller, selectedGroups),
    );
  }

  Widget _refreshLibraryButton(
    AppController controller, {
    bool enabled = true,
  }) {
    return Tooltip(
      message: 'Refresh library',
      child: ObsidianHudIconButton(
        icon: _refreshingLibrary
            ? Icons.hourglass_top_rounded
            : Icons.refresh_rounded,
        onPressed: !enabled || _refreshingLibrary
            ? null
            : () => unawaited(_refreshLibrary(controller)),
      ),
    );
  }

  Future<void> _refreshLibrary(AppController controller) async {
    if (_refreshingLibrary) {
      return;
    }
    setState(() => _refreshingLibrary = true);
    try {
      await controller.refreshLibrary();
      if (!mounted) {
        return;
      }
      final query = _searchController.text.trim();
      if (controller.authState.isAuthorized && query.length >= 2) {
        _runSearch(controller);
      } else {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingLibrary = false);
      }
    }
  }

  void _runSearch(AppController controller) {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      controller.search('', filter: 'all');
      return;
    }
    controller.search(query, filter: 'all');
  }

  void _queueSearch(AppController controller) {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      controller.search('', filter: 'all');
      return;
    }
    if (query.length < 2) {
      controller.search('', filter: 'all');
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      controller.search(query, filter: 'all');
    });
  }

  void _clearSearch(AppController controller) {
    _searchController.clear();
    _searchDebounce?.cancel();
    controller.search('', filter: 'all');
  }

  List<Widget> _downloadedMusicSlivers({
    required AppController controller,
    required List<Track> tracks,
    required List<OfflineArtistGroup> groups,
    required String emptyTitle,
    required String emptyMessage,
    required bool showCollectionList,
    bool showEmpty = true,
  }) {
    return [
      _sectionHeaderSliver('Local Library'),
      if (tracks.isEmpty && showEmpty)
        SliverToBoxAdapter(
          child: EmptyStateText(
            title: emptyTitle,
            message: emptyMessage,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          ),
        )
      else if (tracks.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: _offlineArtistCollectionSliver(
            controller,
            groups,
            showCollectionList,
          ),
        ),
    ];
  }

  List<Widget> _serverArtistSlivers(
    AppController controller, {
    required List<Artist> artists,
    required Map<String, String> authHeadersMap,
    required bool showCollectionList,
    required bool isLoading,
  }) {
    return [
      _sectionHeaderSliver(
        'Server Library',
        subtitle: _serverArtistSubtitle(artists),
      ),
      if (artists.isEmpty && isLoading)
        loadingSliver()
      else if (artists.isEmpty)
        const SliverToBoxAdapter(
          child: EmptyStateText(
            title: 'No server artists',
            message: 'This connected server has no artists yet.',
            padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: showCollectionList
              ? SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index.isOdd) {
                      return const Divider(height: 1);
                    }
                    final artist = artists[index ~/ 2];
                    return ArtistRowTile(
                      artist: artist,
                      coverUrl: _artistCoverUrl(controller, artist),
                      headers: authHeadersMap,
                      onTap: () => _openArtistDetail(artist),
                    );
                  }, childCount: artists.length * 2 - 1),
                )
              : SafeSliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final artist = artists[index];
                    return ArtistCard(
                      artist: artist,
                      coverUrl: _artistCoverUrl(controller, artist),
                      headers: authHeadersMap,
                      onTap: () => _openArtistDetail(artist),
                    );
                  }, childCount: artists.length),
                ),
        ),
        if (isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _connectedSearchSlivers(
    AppController controller, {
    required String query,
    required List<SearchResult> results,
    required bool isSearchLoading,
    required bool hasOfflineResults,
  }) {
    if (query.length < 2) {
      return [
        _statusTextSliver(
          'Type at least 2 characters to search connected server',
        ),
      ];
    }
    if (isSearchLoading) {
      return [
        _sectionHeaderSliver('Connected Server Results'),
        loadingSliver(),
      ];
    }
    if (results.isNotEmpty) {
      return [
        _sectionHeaderSliver(
          'Connected Server Results',
          subtitle: '${results.length} server matches',
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SearchResultsSliver(
            results: results,
            onSelect: (result) => _handleSearchSelect(controller, result),
          ),
        ),
      ];
    }
    if (hasOfflineResults) {
      return [_statusTextSliver('No connected server results')];
    }
    return [_statusTextSliver('No Results')];
  }

  Widget _offlineArtistCollectionSliver(
    AppController controller,
    List<OfflineArtistGroup> groups,
    bool showCollectionList,
  ) {
    if (groups.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final removingTrackIds = _removingTrackIds(controller);
    return showCollectionList
        ? SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index.isOdd) {
                return const Divider(height: 1);
              }
              final group = groups[index ~/ 2];
              final isDeleting = _groupHasRemovingTracks(
                group,
                removingTrackIds,
              );
              return ArtistRowTile(
                artist: group.toArtist(),
                coverUrl: group.coverPath,
                headers: const {},
                onTap: () => _openLocalArtistDetail(group),
                selectionMode: _artistSelectionMode,
                selectable: !isDeleting,
                isDeleting: isDeleting,
                selected: _selectedArtistIds.contains(
                  _artistSelectionKey(group),
                ),
                onSelectionToggle: () => _toggleArtistSelection(group),
              );
            }, childCount: groups.length * 2 - 1),
          )
        : SafeSliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final group = groups[index];
              final isDeleting = _groupHasRemovingTracks(
                group,
                removingTrackIds,
              );
              return ArtistCard(
                artist: group.toArtist(),
                coverUrl: group.coverPath,
                headers: const {},
                onTap: () => _openLocalArtistDetail(group),
                selectionMode: _artistSelectionMode,
                selectable: !isDeleting,
                isDeleting: isDeleting,
                selected: _selectedArtistIds.contains(
                  _artistSelectionKey(group),
                ),
                onSelectionToggle: () => _toggleArtistSelection(group),
              );
            }, childCount: groups.length),
          );
  }

  Future<void> _removeSelectedArtistDownloads(
    AppController controller,
    List<OfflineArtistGroup> groups,
  ) async {
    final ids = groups.map(_artistSelectionKey).toSet();
    final tracks = <Track>[
      for (final group in controller.offlineLibrarySnapshot.artistGroups)
        if (ids.contains(_artistSelectionKey(group)))
          for (final album in group.albums) ...album.tracks,
    ];
    if (tracks.isEmpty) {
      return;
    }
    final label = groups.length == 1
        ? groups.single.name
        : '${groups.length} artists';
    final confirmed = await confirmRemoveDownloadedTracks(
      context,
      tracks,
      label: label,
    );
    if (!confirmed || !mounted) {
      return;
    }
    _clearArtistSelection();
    try {
      await controller.removeDownloadedTracks(
        tracks,
        label: label,
        scope: OfflineDeletionScope.artist(
          id: groups.length == 1 ? groups.single.id : null,
          label: label,
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove $label: $err')));
    }
  }

  List<OfflineArtistGroup> _selectedOfflineArtists(
    List<OfflineArtistGroup> groups,
  ) {
    return groups
        .where(
          (group) => _selectedArtistIds.contains(_artistSelectionKey(group)),
        )
        .toList(growable: false);
  }

  void _toggleArtistSelection(OfflineArtistGroup group) {
    final key = _artistSelectionKey(group);
    setState(() {
      _artistSelectionMode = true;
      if (!_selectedArtistIds.remove(key)) {
        _selectedArtistIds.add(key);
      }
    });
  }

  void _selectAllArtists(Iterable<String> artistIds) {
    setState(() {
      _artistSelectionMode = true;
      _selectedArtistIds
        ..clear()
        ..addAll(artistIds);
    });
  }

  void _deselectAllArtists() {
    setState(() {
      _artistSelectionMode = true;
      _selectedArtistIds.clear();
    });
  }

  void _startArtistSelection() {
    setState(() {
      _artistSelectionMode = true;
      _selectedArtistIds.clear();
    });
  }

  void _clearArtistSelection() {
    setState(() {
      _artistSelectionMode = false;
      _selectedArtistIds.clear();
    });
  }

  String _artistSelectionKey(OfflineArtistGroup group) => group.id;

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

  bool _groupHasRemovingTracks(
    OfflineArtistGroup group,
    Set<String> removingTrackIds,
  ) {
    if (removingTrackIds.isEmpty) {
      return false;
    }
    for (final album in group.albums) {
      for (final track in album.tracks) {
        if (_trackMatchesAnyIdentity(track, removingTrackIds)) {
          return true;
        }
      }
    }
    return false;
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

  Widget _sectionHeaderSliver(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      sliver: SliverToBoxAdapter(
        child: ObsidianSectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _statusTextSliver(String text) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          text,
          style: GoogleFonts.rajdhani(
            color: Colors.white54,
            fontSize: 14,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<Track> _filterOfflineTracks(List<Track> tracks, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return tracks;
    }
    return tracks
        .where((track) {
          final target = '${track.title} ${track.artist} ${track.album}'
              .toLowerCase();
          return target.contains(normalized);
        })
        .toList(growable: false);
  }

  String _serverArtistSubtitle(List<Artist> artists) {
    final label = artists.length == 1 ? 'artist' : 'artists';
    return '${artists.length} server $label loaded';
  }

  void _handleArtistScroll() {
    if (!mounted) {
      return;
    }
    _maybeLoadMoreArtists();
  }

  void _maybeLoadMoreArtists() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    if (_searchController.text.trim().isNotEmpty) {
      return;
    }
    final controller = AppScope.of(context);
    if (!controller.authState.isAuthorized) {
      return;
    }
    if (controller.artistsLoading || !controller.hasMoreArtists) {
      return;
    }
    if (_scrollController.position.extentAfter > 720) {
      return;
    }
    unawaited(controller.loadMoreArtists());
  }

  String? _artistCoverUrl(AppController controller, Artist artist) {
    if (artist.logoRef == null || artist.logoRef!.isEmpty) {
      return null;
    }
    return controller.connection.buildArtistCoverUrl(artist.id, kind: 'logo');
  }

  void _openArtistDetail(Artist artist) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)),
    );
  }

  void _openLocalArtistDetail(OfflineArtistGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LocalArtistDetailScreen(group: group)),
    );
  }

  Future<void> _handleSearchSelect(
    AppController controller,
    SearchResult result,
  ) async {
    try {
      switch (result.kind) {
        case 'artist':
          final artist = await controller.connection.fetchArtistById(result.id);
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          break;
        case 'album':
          final album = await controller.connection.fetchAlbumById(result.id);
          final artist = await controller.connection.fetchArtistById(
            album.artistId,
          );
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          final navigator = Navigator.of(context);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  AlbumDetailScreen(album: album, artistName: album.artist),
            ),
          );
          break;
        case 'track':
          final track = await controller.connection.fetchTrackById(result.id);
          final albumId = track.albumId;
          if (albumId == null || albumId.isEmpty) {
            return;
          }
          final album = await controller.connection.fetchAlbumById(albumId);
          final artist = await controller.connection.fetchArtistById(
            album.artistId,
          );
          await controller.loadTracks(album.id);
          await controller.queueAlbum(album.id, startTrackId: track.id);
          if (!mounted) {
            return;
          }
          _clearSearch(controller);
          final navigator = Navigator.of(context);
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(
                album: album,
                artistName: album.artist.isNotEmpty
                    ? album.artist
                    : track.artist,
              ),
            ),
          );
          break;
        default:
          break;
      }
    } catch (_) {}
  }
}
