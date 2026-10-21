import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/artist_detail_controller.dart';
import 'package:phonolite_app/application/downloads/offline_download_manager.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_releases.dart';
import 'package:phonolite_app/pages/library/album_detail_screen.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/library/widgets/artist_release_sections.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/loading_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_collection_sliver.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_hero.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/collection_view_toggle_button.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class ArtistDetailScreen extends BasePage {
  final Artist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  static String routeNameFor(String artistId) => '/library/server/artist/$artistId';

  @override
  State<ArtistDetailScreen> createState() => ArtistDetailScreenState();
}

class ArtistDetailScreenState extends BasePageState<ArtistDetailScreen> {
  late final ArtistDetailController _feature = bindController(
    ArtistDetailController(AppScope.of(context), widget.artist),
  );

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 16);

  Future<void> _confirmDownloadArtist(
    AppController controller,
    List<Album> albums,
    ArtistDownloadSummary downloadSummary,
  ) async {
    final trackCount = downloadSummary.total;
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Download artist',
      message: trackCount > 0
          ? 'Queue downloads for ${_feature.artist.name} ($trackCount $trackLabel)? This may use significant storage.'
          : 'Queue downloads for every album by ${_feature.artist.name}? This may use significant storage.',
      confirmLabel: 'Download',
      confirmVariant: TechButtonVariant.standard,
      actionChrome: TechButtonChrome.borderless,
    );

    if (!confirmed || !mounted) {
      return;
    }

    await controller.downloadArtist(_feature.artist, albums);
  }

  Future<void> _removeSelectedAlbumDownloads(AppController controller, List<Album> albums) async {
    final downloads = _feature.downloadsForAlbums(controller, albums);

    if (downloads.isEmpty) {
      return;
    }

    final label = albums.length == 1 ? albums.single.title : '${albums.length} albums';
    final confirmed = await confirmRemoveDownloadedDownloads(context, downloads, label: label);

    if (!confirmed || !mounted) {
      return;
    }

    await _feature.removeAlbumDownloads(albums, label);

    if (mounted) {
      _feature.clearAlbumSelection();
    }
  }

  void _openAlbumDetail(Album album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: AlbumDetailScreen.routeNameFor(album.id)),
        builder: (_) =>
            AlbumDetailScreen(album: album, artistName: album.artist.isEmpty ? _feature.artist.name : album.artist),
      ),
    );
  }

  Widget _artistContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required bool isLoading,
    required List<Album> albums,
    required List<Album> headlineAlbums,
    required ArtistReleases releases,
    required bool showCollectionList,
    required Map<String, String> authHeadersMap,
    required String? coverUrl,
    required String? bannerUrl,
    required bool compactHeaderActions,
  }) {
    final downloadSummary = ArtistDetailController.summarizeDownloads(controller, _feature.artist, headlineAlbums);
    final removableAlbumIds = _feature.removableAlbumIds(controller, headlineAlbums);
    final removingAlbumIds = _feature.removingAlbumIds(controller, headlineAlbums);
    final selectedAlbums = _feature.selectedAlbums(headlineAlbums, removableAlbumIds);

    return assemble(
      context,
      navbar: DetailActionHeader(
        backLabel: 'Back to library',
        onBack: () => Navigator.of(context).pop(),
        actions: PageToolbarActions(
          spacing: 10,
          runSpacing: 10,
          children: _feature.albumSelectionMode
              ? [
                  DownloadSelectionToolbar(
                    selectedCount: selectedAlbums.length,
                    totalCount: removableAlbumIds.length,
                    onCancel: _feature.clearAlbumSelection,
                    onSelectAll: () => _feature.selectAllAlbums(removableAlbumIds),
                    onDeselectAll: _feature.deselectAllAlbums,
                    onRemove: selectedAlbums.isEmpty
                        ? null
                        : () => _removeSelectedAlbumDownloads(controller, selectedAlbums),
                  ),
                ]
              : [
                  TechButton(
                    label: downloadSummary.label,
                    icon: downloadSummary.isComplete ? PhonoliteIcons.circleCheck : PhonoliteIcons.download,
                    iconOnly: compactHeaderActions,
                    tooltip: downloadSummary.label,
                    chrome: TechButtonChrome.borderless,
                    onTap: !isLoading && downloadSummary.canStart
                        ? () => _confirmDownloadArtist(controller, headlineAlbums, downloadSummary)
                        : null,
                  ),
                  CollectionViewToggleButton(
                    isListView: showCollectionList,
                    onPressed: controller.toggleCollectionListMode,
                  ),
                ],
        ),
      ),
      body: PageBody.slivers(
        slivers: [
          PageSliverBox(
            top: 0,
            bottom: 24,
            child: ArtistHero(
              artist: _feature.artist,
              coverUrl: coverUrl,
              bannerUrl: bannerUrl,
              headers: authHeadersMap,
            ),
          ),
          if (!isLoading && albums.isNotEmpty) ArtistReleaseHeading(title: 'Albums', count: albums.length),
          if (isLoading && albums.isEmpty)
            loadingSliver()
          else if (albums.isEmpty && releases.collabAlbums.isEmpty)
            const PageSliverBox(top: 8, bottom: 24, child: EmptyStateText(title: 'Artist has no albums'))
          else if (albums.isNotEmpty)
            PageSliverPadding(
              top: 0,
              bottom: 32,
              sliver: AlbumCollectionSliver<Album>(
                items: albums,
                isListView: showCollectionList,
                albumFor: (album) => album,
                coverFor: (album) => _feature.albumCoverUrl(controller, album),
                headers: authHeadersMap,
                onOpen: _openAlbumDetail,
                selectionMode: _feature.albumSelectionMode,
                isDeleting: (album) => removingAlbumIds.contains(_feature.albumSelectionKey(album)),
                selectable: (album) =>
                    !removingAlbumIds.contains(_feature.albumSelectionKey(album)) &&
                    removableAlbumIds.contains(_feature.albumSelectionKey(album)),
                selected: (album) => _feature.selectedAlbumIds.contains(_feature.albumSelectionKey(album)),
                onSelectionToggle: _feature.toggleAlbumSelection,
              ),
            ),
          if (!isLoading && releases.collabAlbums.isNotEmpty)
            ArtistContributionSliver(
              title: 'Collab albums',
              entries: releases.collabAlbums,
              isListView: showCollectionList,
              coverFor: (album) => _feature.albumCoverUrl(controller, album),
              headers: authHeadersMap,
              onOpen: _openAlbumDetail,
              selectionMode: _feature.albumSelectionMode,
              selected: (entry) => _feature.selectedAlbumIds.contains(_feature.albumSelectionKey(entry.album)),
              selectable: (entry) =>
                  entry.isAlbumArtist &&
                  !removingAlbumIds.contains(_feature.albumSelectionKey(entry.album)) &&
                  removableAlbumIds.contains(_feature.albumSelectionKey(entry.album)),
              isDeleting: (entry) => removingAlbumIds.contains(_feature.albumSelectionKey(entry.album)),
              onSelectionToggle: (entry) => _feature.toggleAlbumSelection(entry.album),
            ),
          if (!isLoading && releases.appearsOn.isNotEmpty)
            ArtistContributionSliver(
              title: 'Appears on',
              entries: releases.appearsOn,
              isListView: showCollectionList,
              coverFor: (album) => _feature.albumCoverUrl(controller, album),
              headers: authHeadersMap,
              onOpen: _openAlbumDetail,
            ),
          if (!isLoading && releases.otherCredits.isNotEmpty)
            ArtistContributionSliver(
              title: 'Other credits',
              entries: releases.otherCredits,
              isListView: showCollectionList,
              coverFor: (album) => _feature.albumCoverUrl(controller, album),
              headers: authHeadersMap,
              onOpen: _openAlbumDetail,
            ),
          if (isLoading && albums.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);
    final authHeadersMap = authHeaders(controller);
    final coverUrl = _feature.artist.logoRef == null || _feature.artist.logoRef!.isEmpty
        ? null
        : controller.catalog.buildArtistCoverUrl(_feature.artist.id, kind: 'logo', ref: _feature.artist.logoRef);
    final bannerUrl = _feature.artist.bannerRef == null || _feature.artist.bannerRef!.isEmpty
        ? null
        : controller.catalog.buildArtistCoverUrl(_feature.artist.id, kind: 'banner', ref: _feature.artist.bannerRef);
    final compactHeaderActions = isCompactListWidth(context);

    return StreamBuilder<bool>(
      stream: controller.albumsLoadingStream,
      initialData: controller.albumsLoading,
      builder: (context, loadingSnapshot) {
        final isLoading = loadingSnapshot.data ?? false;

        return StreamBuilder<ArtistReleases>(
          stream: controller.artistReleasesStream,
          initialData: controller.artistReleases,
          builder: (context, snapshot) {
            final releases = snapshot.data ?? const ArtistReleases();
            final albums = releases.albums;
            final headlineAlbums = releases.headlineAlbums;

            return StreamBuilder<bool>(
              stream: controller.collectionListModeStream,
              initialData: controller.collectionListMode,
              builder: (context, viewModeSnapshot) {
                final showCollectionList = viewModeSnapshot.data ?? controller.collectionListMode;

                return StreamBuilder<OfflineDownloadSnapshot>(
                  stream: controller.offlineDownloadSnapshotStream,
                  initialData: controller.offlineDownloadSnapshot,
                  builder: (context, _) => _artistContent(
                    context,
                    assemble,
                    controller,
                    isLoading: isLoading,
                    albums: albums,
                    headlineAlbums: headlineAlbums,
                    releases: releases,
                    showCollectionList: showCollectionList,
                    authHeadersMap: authHeadersMap,
                    coverUrl: coverUrl,
                    bannerUrl: bannerUrl,
                    compactHeaderActions: compactHeaderActions,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
