import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/local_artist_detail_controller.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/pages/library/local_album_detail_screen.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/library/widgets/artist_release_sections.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_collection_sliver.dart';
import 'package:phonolite_app/ui/shared/music/artists/artist_hero.dart';
import 'package:phonolite_app/ui/shared/music/collection_view_toggle_button.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class LocalArtistDetailScreen extends BasePage {
  final OfflineArtistGroup group;

  const LocalArtistDetailScreen({super.key, required this.group});

  static String routeNameFor(String artistId) => '/library/local/artist/$artistId';

  @override
  State<LocalArtistDetailScreen> createState() => _LocalArtistDetailScreenState();
}

class _LocalArtistDetailScreenState extends BasePageState<LocalArtistDetailScreen> {
  late final LocalArtistDetailController _feature = bindController(
    LocalArtistDetailController(AppScope.of(context), widget.group),
  );

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 16);

  void _openAlbum(BuildContext context, OfflineAlbumGroup album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: LocalAlbumDetailScreen.routeNameFor(album.id)),
        builder: (_) => LocalAlbumDetailScreen(album: album),
      ),
    );
  }

  Future<void> _removeSelectedAlbumDownloads(AppController controller, List<OfflineAlbumGroup> albums) async {
    final tracks = _feature.tracksForAlbums(albums);

    if (tracks.isEmpty) {
      return;
    }

    final label = albums.length == 1 ? albums.single.title : '${albums.length} albums';
    final confirmed = await confirmRemoveDownloadedTracks(context, tracks, label: label);

    if (!confirmed || !mounted) {
      return;
    }

    await _feature.removeAlbumDownloads(albums, label);

    if (mounted) {
      _feature.clearAlbumSelection();
    }
  }

  Widget _editAlbumSelectionButton(VoidCallback? onPressed) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(iconWidget: const EditIcon(), onPressed: onPressed),
    );
  }

  Widget _localArtistContent(BuildContext context, PageAssembler assemble, AppController controller) {
    final group = _feature.currentGroup(controller);
    final albums = group.soloAlbums;
    final releases = group.releases;
    final removableAlbumIds = _feature.removableAlbumIds(group.headlineAlbums);
    final selectedAlbums = _feature.selectedAlbums(group.headlineAlbums, removableAlbumIds);
    final removingTrackIds = _feature.removingTrackIds(controller);

    return StreamBuilder<bool>(
      stream: controller.collectionListModeStream,
      initialData: controller.collectionListMode,
      builder: (context, viewModeSnapshot) {
        final showCollectionList = viewModeSnapshot.data ?? controller.collectionListMode;

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
                      _editAlbumSelectionButton(removableAlbumIds.isNotEmpty ? _feature.startAlbumSelection : null),
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
                  artist: group.toArtist(),
                  coverUrl: group.coverPath,
                  bannerUrl: group.bannerPath,
                  headers: const {},
                ),
              ),
              if (albums.isNotEmpty) ArtistReleaseHeading(title: 'Albums', count: albums.length),
              if (albums.isEmpty && releases.collabAlbums.isEmpty)
                const PageSliverBox(top: 8, bottom: 24, child: EmptyStateText(title: 'Artist has no downloaded albums'))
              else if (albums.isNotEmpty)
                PageSliverPadding(
                  top: 0,
                  bottom: 32,
                  sliver: AlbumCollectionSliver<OfflineAlbumGroup>(
                    items: albums,
                    isListView: showCollectionList,
                    albumFor: (album) => album.toAlbum(),
                    coverFor: (album) => album.coverPath ?? '',
                    onOpen: (album) => _openAlbum(context, album),
                    selectionMode: _feature.albumSelectionMode,
                    isDeleting: (album) => _feature.albumHasRemovingTracks(album, removingTrackIds),
                    selectable: (album) =>
                        !_feature.albumHasRemovingTracks(album, removingTrackIds) &&
                        removableAlbumIds.contains(_feature.albumSelectionKey(album)),
                    selected: (album) => _feature.selectedAlbumIds.contains(_feature.albumSelectionKey(album)),
                    onSelectionToggle: _feature.toggleAlbumSelection,
                  ),
                ),
              if (releases.collabAlbums.isNotEmpty)
                ArtistContributionSliver(
                  title: 'Collab albums',
                  entries: releases.collabAlbums,
                  isListView: showCollectionList,
                  coverFor: (album) => group.albums.firstWhere((item) => item.id == album.id).coverPath ?? '',
                  onOpen: (album) => _openAlbum(context, group.albums.firstWhere((item) => item.id == album.id)),
                  selectionMode: _feature.albumSelectionMode,
                  selected: (entry) => _feature.selectedAlbumIds.contains(entry.album.id),
                  selectable: (entry) =>
                      entry.isAlbumArtist &&
                      removableAlbumIds.contains(entry.album.id) &&
                      !_feature.albumHasRemovingTracks(
                        group.albums.firstWhere((album) => album.id == entry.album.id),
                        removingTrackIds,
                      ),
                  isDeleting: (entry) => _feature.albumHasRemovingTracks(
                    group.albums.firstWhere((album) => album.id == entry.album.id),
                    removingTrackIds,
                  ),
                  onSelectionToggle: (entry) =>
                      _feature.toggleAlbumSelection(group.albums.firstWhere((album) => album.id == entry.album.id)),
                ),
              if (releases.appearsOn.isNotEmpty)
                ArtistContributionSliver(
                  title: 'Appears on',
                  entries: releases.appearsOn,
                  isListView: showCollectionList,
                  coverFor: (album) => group.albums.firstWhere((item) => item.id == album.id).coverPath ?? '',
                  onOpen: (album) => _openAlbum(context, group.albums.firstWhere((item) => item.id == album.id)),
                ),
              if (releases.otherCredits.isNotEmpty)
                ArtistContributionSliver(
                  title: 'Other credits',
                  entries: releases.otherCredits,
                  isListView: showCollectionList,
                  coverFor: (album) => group.albums.firstWhere((item) => item.id == album.id).coverPath ?? '',
                  onOpen: (album) => _openAlbum(context, group.albums.firstWhere((item) => item.id == album.id)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<List<OfflineTrackDownload>>(
      stream: controller.offlineDownloadsStream,
      initialData: controller.offlineDownloads,
      builder: (context, _) => _localArtistContent(context, assemble, controller),
    );
  }
}
