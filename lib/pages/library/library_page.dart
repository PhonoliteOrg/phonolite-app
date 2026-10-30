import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_controller.dart';
import 'package:phonolite_app/application/controllers/library/library_navigation_controller.dart';
import 'package:phonolite_app/application/controllers/settings/display_settings_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/search_result.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/pages/library/artist_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/pages/library/local_artist_detail_screen.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_manager_panel.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/library/widgets/library_section_slivers.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_results_sliver.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/reload_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/loading_widgets.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_collection_sliver.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/collection_view_toggle_button.dart';
import 'package:phonolite_app/ui/shared/music/source_section_slivers.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class LibraryPage extends BasePage {
  final DisplaySettingsController? displaySettings;

  const LibraryPage({super.key, this.displaySettings});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends BasePageState<LibraryPage> {
  static const double _searchFieldHeight = 48;

  late final LibraryNavigationController _navigation = bindController(
    LibraryNavigationController(AppScope.of(context)),
  );
  late final LibraryController _feature = bindController(LibraryController(AppScope.of(context)));
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  DisplaySettingsController get _displaySettings => widget.displaySettings ?? DisplaySettingsController.instance;

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();
    _scrollController.addListener(_handleArtistScroll);

    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _feature.loadIfNeeded();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreArtists());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleArtistScroll);
    _scrollController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  Widget _buildServerLibrary(AppController controller, PageAssembler assemble) {
    final authHeadersMap = authHeaders(controller);

    return ColoredBox(
      color: Colors.transparent,
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

                      if (query.isEmpty && artists.isNotEmpty && controller.hasMoreArtists && !isLoading) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMoreArtists());
                      }

                      return StreamBuilder<bool>(
                        stream: controller.collectionListModeStream,
                        initialData: controller.collectionListMode,
                        builder: (context, viewModeSnapshot) {
                          final showCollectionList = viewModeSnapshot.data ?? controller.collectionListMode;

                          return StreamBuilder<OfflineLibrarySnapshot>(
                            stream: controller.offlineLibrarySnapshotStream,
                            initialData: controller.offlineLibrarySnapshot,
                            builder: (context, librarySnapshot) => _connectedLibraryContent(
                              context,
                              assemble,
                              controller,
                              librarySnapshot: librarySnapshot,
                              results: results,
                              isLoading: isLoading,
                              isSearchLoading: isSearchLoading,
                              artists: artists,
                              query: query,
                              showCollectionList: showCollectionList,
                              authHeadersMap: authHeadersMap,
                            ),
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

  Widget _buildOfflineLibrary(AppController controller, PageAssembler assemble) {
    return ColoredBox(
      color: Colors.transparent,
      child: StreamBuilder<OfflineLibrarySnapshot>(
        stream: controller.offlineLibrarySnapshotStream,
        initialData: controller.offlineLibrarySnapshot,
        builder: (context, snapshot) {
          return StreamBuilder<bool>(
            stream: controller.collectionListModeStream,
            initialData: controller.collectionListMode,
            builder: (context, viewModeSnapshot) => _offlineLibraryContent(
              context,
              assemble,
              controller,
              snapshot: snapshot,
              viewModeSnapshot: viewModeSnapshot,
            ),
          );
        },
      ),
    );
  }

  Widget _downloadManagerButton({bool enabled = true, double iconSize = PageToolbarActionLayout.regularIconSize}) {
    return Tooltip(
      message: 'Download Manager',
      child: ObsidianHudIconButton(
        icon: PhonoliteIcons.download,
        size: iconSize,
        onPressed: enabled ? () => unawaited(showDownloadManagerPanel(context)) : null,
      ),
    );
  }

  Widget _editLibraryButton(VoidCallback? onPressed, {double iconSize = PageToolbarActionLayout.regularIconSize}) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(iconWidget: const EditIcon(), size: iconSize, onPressed: onPressed),
    );
  }

  Widget _collectionViewButton({
    required bool isListView,
    required VoidCallback? onPressed,
    double iconSize = PageToolbarActionLayout.regularIconSize,
  }) => CollectionViewToggleButton(
    isListView: isListView,
    onPressed: onPressed,
    semanticLabel: 'Library collection view',
    iconSize: iconSize,
  );

  Widget _artistSelectionToolbar({
    required AppController controller,
    required List<OfflineArtistGroup> groups,
    required List<OfflineArtistGroup> selectedGroups,
  }) {
    return DownloadSelectionToolbar(
      selectedCount: selectedGroups.length,
      totalCount: groups.where((group) => group.tracksForArtist.isNotEmpty).length,
      onCancel: _feature.clearArtistSelection,
      onSelectAll: () => _feature.selectAllArtists(
        groups.where((group) => group.tracksForArtist.isNotEmpty).map(_feature.artistSelectionKey),
      ),
      onDeselectAll: _feature.deselectAllArtists,
      onRemove: selectedGroups.isEmpty ? null : () => _removeSelectedArtistDownloads(selectedGroups),
    );
  }

  Widget _refreshLibraryButton(
    AppController controller, {
    bool enabled = true,
    double iconSize = PageToolbarActionLayout.regularIconSize,
  }) {
    return Tooltip(
      message: 'Refresh library',
      child: ObsidianHudIconButton(
        icon: _feature.refreshingLibrary ? PhonoliteIcons.hourglass : null,
        iconWidget: _feature.refreshingLibrary ? null : const ReloadIcon(),
        size: iconSize,
        onPressed: !enabled || _feature.refreshingLibrary ? null : () => unawaited(_feature.refreshLibrary(controller)),
      ),
    );
  }

  void _clearSearch(AppController controller) {
    _searchController.clear();
    _feature.clearSearch();
  }

  List<Widget> _downloadedMusicSlivers({
    required AppController controller,
    required List<Track> tracks,
    required List<OfflineArtistGroup> groups,
    required String emptyTitle,
    required String emptyMessage,
    required bool showCollectionList,
  }) {
    return [
      LibrarySectionHeading(title: 'Local Library'),
      if (tracks.isEmpty)
        SliverToBoxAdapter(
          child: EmptyStateText(
            title: emptyTitle,
            message: emptyMessage,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          ),
        )
      else if (tracks.isNotEmpty)
        PageSliverPadding(
          top: 0,
          bottom: 32,
          sliver: _offlineArtistCollectionSliver(controller, groups, showCollectionList),
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
    final snapshot = controller.artistBrowseSnapshot;
    final windowed = snapshot.total > 0;
    final indices = windowed ? snapshot.indices : List<int>.generate(artists.length, (index) => index);

    Artist? sourceAt(int index) => windowed ? snapshot.at(index)?.toArtist() : artists[index];

    Artist artistAt(int index) {
      final source = sourceAt(index);

      return source == null
          ? Artist(id: 'unloaded-artist-$index', name: 'Loading artist…', albumCount: 0)
          : _feature.visibleArtist(source);
    }

    void visibilityChanged(int index, bool visible) {
      final artist = sourceAt(index);

      if (artist != null) {
        _feature.artistVisibilityChanged(artist, visible);
      } else if (visible) {
        unawaited(controller.loadArtistBrowsePage(index));
      }

      if (visible && !windowed && !_displaySettings.settings.libraryLocalFirst && index == indices.length - 1) {
        // Local sections below the server catalogue must not delay legacy paging.
        _feature.loadMoreArtists(0);
      }
    }

    return [
      LibrarySectionHeading(title: 'Server Library'),
      if (indices.isEmpty && isLoading)
        loadingSliver()
      else if (indices.isEmpty)
        const SliverToBoxAdapter(
          child: EmptyStateText(
            title: 'No server artists',
            message: 'This connected server has no artists yet.',
            padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
          ),
        )
      else ...[
        PageSliverPadding(
          top: 0,
          bottom: 32,
          sliver: ArtistCollectionSliver<int>(
            items: indices,
            isListView: showCollectionList,
            artistFor: artistAt,
            coverFor: (index) => _feature.artistCoverUrl(controller, artistAt(index)),
            headers: authHeadersMap,
            onOpen: (index) {
              if (sourceAt(index) != null) {
                _openArtistDetail(artistAt(index));
              }
            },
            onVisibilityChanged: visibilityChanged,
            visibilityScope: controller.connection.sessionRevision,
          ),
        ),
        if (isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
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
  }) {
    if (query.length < 2) {
      return [
        LibrarySectionHeading(title: 'Server Library Results'),
        LibraryStatusSliver(message: 'Type at least 2 characters to search connected server'),
      ];
    }

    if (isSearchLoading) {
      return [LibrarySectionHeading(title: 'Server Library Results'), loadingSliver()];
    }

    if (results.isNotEmpty) {
      return [
        LibrarySectionHeading(title: 'Server Library Results', subtitle: '${results.length} server matches'),
        PageSliverPadding(
          top: 0,
          bottom: 24,
          sliver: SearchResultsSliver(
            results: results,
            catalog: controller.catalog,
            headers: authHeaders(controller),
            onSelect: (result) => _handleSearchSelect(controller, result),
          ),
        ),
      ];
    }

    return [
      LibrarySectionHeading(title: 'Server Library Results', subtitle: '0 server matches'),
      LibraryStatusSliver(message: 'No server results'),
    ];
  }

  List<Widget> _localSearchSlivers(AppController controller, {required List<SearchResult> results}) => [
    LibrarySectionHeading(title: 'Local Library Results', subtitle: '${results.length} local matches'),
    if (results.isEmpty)
      LibraryStatusSliver(message: 'No local results')
    else
      PageSliverPadding(
        top: 0,
        bottom: 24,
        sliver: SearchResultsSliver(
          results: results,
          useLocalArtwork: true,
          onSelect: (result) => _handleLocalSearchSelect(controller, result),
        ),
      ),
  ];

  Widget _offlineArtistCollectionSliver(
    AppController controller,
    List<OfflineArtistGroup> groups,
    bool showCollectionList,
  ) {
    final removingTrackIds = _feature.removingTrackIds(controller);

    return ArtistCollectionSliver<OfflineArtistGroup>(
      items: groups,
      isListView: showCollectionList,
      artistFor: (group) => group.toArtist(),
      coverFor: (group) => group.coverPath,
      onOpen: _openLocalArtistDetail,
      selectionMode: _feature.artistSelectionMode,
      isDeleting: (group) => _feature.groupHasRemovingTracks(group, removingTrackIds),
      selectable: (group) =>
          !_feature.groupHasRemovingTracks(group, removingTrackIds) && group.tracksForArtist.isNotEmpty,
      selected: (group) => _feature.selectedArtistIds.contains(_feature.artistSelectionKey(group)),
      onSelectionToggle: _feature.toggleArtistSelection,
    );
  }

  Future<void> _removeSelectedArtistDownloads(List<OfflineArtistGroup> groups) async {
    final tracks = _feature.tracksForArtists(groups);

    if (tracks.isEmpty) {
      return;
    }

    final label = groups.length == 1 ? groups.single.name : '${groups.length} artists';
    final confirmed = await confirmRemoveDownloadedTracks(context, tracks, label: label);

    if (!confirmed || !mounted) {
      return;
    }

    await _feature.removeArtistDownloads(groups, label);
  }

  void _handleSearchTextChanged() => _feature.setQuery(_searchController.text);

  void _handleArtistScroll() {
    if (!mounted) {
      return;
    }

    _maybeLoadMoreArtists();
  }

  void _maybeLoadMoreArtists() {
    if (mounted && _scrollController.hasClients && _scrollController.position.hasContentDimensions) {
      _feature.loadMoreArtists(_scrollController.position.extentAfter);
    }
  }

  void _openArtistDetail(Artist artist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: ArtistDetailScreen.routeNameFor(artist.id)),
        builder: (_) => ArtistDetailScreen(artist: artist),
      ),
    );
  }

  void _openLocalArtistDetail(OfflineArtistGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: LocalArtistDetailScreen.routeNameFor(group.id)),
        builder: (_) => LocalArtistDetailScreen(group: group),
      ),
    );
  }

  Future<void> _handleLocalSearchSelect(AppController controller, SearchResult result) =>
      _openSearchResult(controller, result, local: true);

  Future<void> _handleSearchSelect(AppController controller, SearchResult result) =>
      _openSearchResult(controller, result, local: false);

  Future<void> _openSearchResult(AppController controller, SearchResult result, {required bool local}) async {
    final destination = await _navigation.search(result, local: local);

    if (!mounted || destination == null) {
      return;
    }

    _clearSearch(controller);

    final navigator = Navigator.of(context);
    final localArtist = destination.localArtist;

    if (localArtist != null) {
      navigator.push(MaterialPageRoute(builder: (_) => LocalArtistDetailScreen(group: localArtist)));
    }

    final localAlbum = destination.localAlbum;

    if (localAlbum != null) {
      navigator.push(MaterialPageRoute(builder: (_) => LocalAlbumDetailScreen(album: localAlbum)));
    }

    final artist = destination.artist;

    if (artist != null) {
      navigator.push(MaterialPageRoute(builder: (_) => ArtistDetailScreen(artist: artist)));
    }

    final album = destination.album;

    if (album != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => AlbumDetailScreen(album: album, artistName: destination.artistName),
        ),
      );
    }
  }

  Widget _libraryActions(
    BuildContext context,
    AppController controller, {
    required List<OfflineArtistGroup> groups,
    required List<OfflineArtistGroup> selectedGroups,
    required bool showCollectionList,
  }) {
    if (_feature.artistSelectionMode) {
      return _artistSelectionToolbar(controller: controller, groups: groups, selectedGroups: selectedGroups);
    }

    final layout = PageToolbarActionLayout.of(context);

    return PageToolbarActions(
      spacing: layout.spacing,
      runSpacing: layout.compact ? 4 : 8,
      children: [
        _refreshLibraryButton(controller, iconSize: layout.iconSize),
        _downloadManagerButton(iconSize: layout.iconSize),
        _editLibraryButton(groups.isNotEmpty ? _feature.startArtistSelection : null, iconSize: layout.iconSize),
        _collectionViewButton(
          isListView: showCollectionList,
          onPressed: controller.toggleCollectionListMode,
          iconSize: layout.iconSize,
        ),
      ],
    );
  }

  void _clearOfflineSearch() {
    _searchController.clear();
    setState(() {});
  }

  bool _handleScrollStart(BuildContext context, ScrollStartNotification notification) {
    // Clamped short lists produce no ScrollUpdateNotification on Android.
    // Recognize the drag itself; wheel scrolling and input-field scrolling
    // must retain focus.
    if (notification.depth == 0 && notification.dragDetails != null) {
      FocusScope.of(context).unfocus();
    }

    return false;
  }

  Widget _connectedLibraryContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AsyncSnapshot<OfflineLibrarySnapshot> librarySnapshot,
    required List<SearchResult> results,
    required bool isLoading,
    required bool isSearchLoading,
    required List<Artist> artists,
    required String query,
    required bool showCollectionList,
    required Map<String, String> authHeadersMap,
  }) {
    final offlineSnapshot = librarySnapshot.data ?? controller.offlineLibrarySnapshot;
    final offlineTracks = offlineSnapshot.tracks;
    final offlineGroups = offlineSnapshot.artistGroups;

    final localResults = _feature.localResults(offlineTracks, offlineGroups, revision: offlineSnapshot.revision);
    final selectedGroups = _feature.selectedOfflineArtists(offlineGroups);

    final localSlivers = query.isEmpty
        ? _downloadedMusicSlivers(
            controller: controller,
            tracks: offlineTracks,
            groups: offlineGroups,
            emptyTitle: 'No downloaded tracks',
            emptyMessage: 'Download tracks from a connected server to keep them here.',
            showCollectionList: showCollectionList,
          )
        : _localSearchSlivers(controller, results: localResults);
    final serverSlivers = query.isEmpty
        ? _serverArtistSlivers(
            controller,
            artists: artists,
            authHeadersMap: authHeadersMap,
            showCollectionList: showCollectionList,
            isLoading: isLoading,
          )
        : _connectedSearchSlivers(controller, query: query, results: results, isSearchLoading: isSearchLoading);

    return ListenableBuilder(
      listenable: _displaySettings,
      builder: (context, _) => assemble(
        context,
        navbar: LibraryHeader(
          trailing: _libraryActions(
            context,
            controller,
            groups: offlineGroups,
            selectedGroups: selectedGroups,
            showCollectionList: showCollectionList,
          ),
        ),
        body: PageBody.slivers(
          pinTopInset: true,
          physics: const AlwaysScrollableScrollPhysics(),
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            PageSliverBox(
              pinned: true,
              top: 12,
              bottom: 12,
              child: SearchHud(
                controller: _searchController,
                height: _searchFieldHeight,
                glassBackground: true,
                onSubmit: () => _feature.runSearch(controller),
                onChanged: () => _feature.queueSearch(controller),
                onClear: () => _clearSearch(controller),
              ),
            ),
            ...orderedSourceSlivers(
              localFirst: _displaySettings.settings.libraryLocalFirst,
              localSlivers: localSlivers,
              serverSlivers: serverSlivers,
            ),
          ],
        ),
      ),
    );
  }

  Widget _offlineLibraryContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AsyncSnapshot<OfflineLibrarySnapshot> snapshot,
    required AsyncSnapshot<bool> viewModeSnapshot,
  }) {
    final showCollectionList = viewModeSnapshot.data ?? controller.collectionListMode;
    final query = _searchController.text.trim();
    final offlineSnapshot = snapshot.data ?? controller.offlineLibrarySnapshot;
    final tracks = offlineSnapshot.tracks;
    final groups = offlineSnapshot.artistGroups;

    final localResults = _feature.localResults(tracks, groups, revision: offlineSnapshot.revision);
    final selectedGroups = _feature.selectedOfflineArtists(groups);

    return assemble(
      context,
      navbar: LibraryHeader(
        trailing: _libraryActions(
          context,
          controller,
          groups: groups,
          selectedGroups: selectedGroups,
          showCollectionList: showCollectionList,
        ),
      ),
      body: PageBody.slivers(
        pinTopInset: true,
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          PageSliverBox(
            pinned: true,
            top: 12,
            bottom: 12,
            child: SearchHud(
              controller: _searchController,
              height: _searchFieldHeight,
              glassBackground: true,
              onSubmit: () => setState(() {}),
              onChanged: () => setState(() {}),
              onClear: _clearOfflineSearch,
            ),
          ),
          if (query.isNotEmpty)
            ..._localSearchSlivers(controller, results: localResults)
          else if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateText(
                title: 'No downloaded tracks',
                message: 'Connect to a server and download tracks to listen offline.',
              ),
            )
          else
            PageSliverPadding(
              top: 0,
              bottom: 32,
              sliver: _offlineArtistCollectionSliver(controller, groups, showCollectionList),
            ),
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) => _handleScrollStart(context, notification),
      child: StreamBuilder<AuthState>(
        stream: controller.authStream,
        initialData: controller.authState,
        builder: (context, snapshot) {
          final authState = snapshot.data ?? controller.authState;

          if (!authState.isAuthorized) {
            return _buildOfflineLibrary(controller, assemble);
          }

          return _buildServerLibrary(controller, assemble);
        },
      ),
    );
  }
}
