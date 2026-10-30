import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/album_detail_controller.dart';
import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/loading_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_hero.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/banner_playback_button.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_sliver_list.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class AlbumDetailScreen extends BasePage {
  final Album album;
  final String artistName;

  const AlbumDetailScreen({super.key, required this.album, required this.artistName});

  static String routeNameFor(String albumId) => '/library/server/album/$albumId';

  @override
  State<AlbumDetailScreen> createState() => AlbumDetailScreenState();
}

class AlbumDetailScreenState extends BasePageState<AlbumDetailScreen> {
  late final AlbumDetailController _feature = bindController(AlbumDetailController(AppScope.of(context), widget.album));

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 16);

  Future<void> _removeDownloads(List<Track> tracks, String label) async {
    if (tracks.isEmpty) {
      return;
    }

    final confirmed = await confirmRemoveDownloadedTracks(context, tracks, label: label);

    if (!confirmed || !mounted) {
      return;
    }

    await _feature.removeDownloads(tracks, label: label);

    if (mounted) {
      _feature.clearSelection();
    }
  }

  Future<void> _playAlbum(AppController controller) async {
    controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.server);
    await controller.queueAlbum(_feature.album.id);
  }

  Widget _albumContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required bool isLoading,
    required List<Track> tracks,
    required PlaybackState playback,
    required String? playingId,
    required Map<String, String> authHeadersMap,
    required String coverUrl,
    required bool compactHeaderActions,
  }) {
    final downloadSummary = AlbumDetailController.summarizeDownloads(controller, tracks, albumId: _feature.album.id);
    final removableTracks = _feature.removableTracks(controller, tracks);
    final selectedTracks = _feature.selectedTracks(removableTracks);

    return assemble(
      context,
      navbar: DetailActionHeader(
        backLabel: 'Back to artist',
        onBack: () => Navigator.of(context).pop(),
        actions: PageToolbarActions(
          spacing: 10,
          runSpacing: 10,
          children: _feature.selectionMode
              ? [
                  DownloadSelectionToolbar(
                    selectedCount: selectedTracks.length,
                    totalCount: removableTracks.length,
                    onCancel: _feature.clearSelection,
                    onSelectAll: () => _feature.selectAll(removableTracks),
                    onDeselectAll: _feature.deselectAll,
                    onRemove: selectedTracks.isEmpty
                        ? null
                        : () => _removeDownloads(selectedTracks, _feature.album.title),
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
                        ? () => controller.downloadAlbum(_feature.album, tracks)
                        : null,
                  ),
                ],
        ),
      ),
      body: PageBody.slivers(
        slivers: [
          PageSliverBox(
            top: 0,
            bottom: 16,
            child: AlbumHero(
              album: _feature.album,
              coverUrl: coverUrl,
              headers: authHeadersMap,
              actions: BannerPlaybackButton(
                message: 'Play album',
                visible: !_feature.selectionMode,
                onPressed: isLoading || tracks.isEmpty ? null : () => _playAlbum(controller),
              ),
            ),
          ),
          if (isLoading && tracks.isEmpty)
            loadingSliver()
          else if (tracks.isEmpty)
            const PageSliverBox(
              top: 24,
              bottom: 0,
              child: EmptyStateText(title: 'No tracks', message: 'Pick another album to see tracks.'),
            ),
          if (!isLoading && tracks.isNotEmpty)
            PageSliverPadding(
              top: 0,
              bottom: 24,
              sliver: TrackSliverList(
                tracks: tracks,
                useAlbumTrackNumbers: true,
                actionsInMenu: true,
                isPlayingTrack: (track) => playback.isPlaying && playingId == track.id,
                onTrackTap: (track) => controller.queueAlbum(_feature.album.id, startTrackId: track.id),
                onTrackAddToPlaylist: (track) =>
                    showAddToPlaylistModalForTrack(context, track, scope: ActionScope.server),
                onTrackDownload: controller.downloadTrack,
                onTrackLike: controller.toggleLike,
                selectionMode: _feature.selectionMode,
                canSelectTrack: (track) => _feature.canRemoveTrack(controller, track),
                isTrackSelected: (track) => _feature.selectedTrackIds.contains(_feature.selectionKey(track)),
                onTrackSelectionToggle: (track) => _feature.toggleSelection(controller, track),
                offlineDownloadForTrack: (track) => controller.offlineDownloadForTrack(track.id),
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
    final coverUrl = controller.catalog.buildAlbumCoverUrl(_feature.album.id);
    final compactHeaderActions = isCompactListWidth(context);

    return StreamBuilder<bool>(
      stream: controller.tracksLoadingStream,
      initialData: controller.tracksLoading,
      builder: (context, loadingSnapshot) {
        final isLoading = loadingSnapshot.data ?? false;

        return StreamBuilder<List<Track>>(
          stream: controller.tracksStream,
          initialData: controller.tracks,
          builder: (context, snapshot) {
            final tracks = snapshot.data ?? [];

            return StreamBuilder<PlaybackState>(
              stream: controller.playbackStream,
              initialData: controller.playbackState,
              builder: (context, playbackSnapshot) {
                final playback = playbackSnapshot.data ?? controller.playbackState;
                final playingId = playback.track?.id;

                return StreamBuilder<OfflineDownloadSnapshot>(
                  stream: controller.offlineDownloadSnapshotStream,
                  initialData: controller.offlineDownloadSnapshot,
                  builder: (context, _) => _albumContent(
                    context,
                    assemble,
                    controller,
                    isLoading: isLoading,
                    tracks: tracks,
                    playback: playback,
                    playingId: playingId,
                    authHeadersMap: authHeadersMap,
                    coverUrl: coverUrl,
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
