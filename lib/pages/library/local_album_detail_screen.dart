import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/library/local_album_detail_controller.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/empty_state.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_hero.dart';
import 'package:phonolite_app/ui/shared/music/banner_playback_button.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_sliver_list.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_scroll_view.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class LocalAlbumDetailScreen extends BasePage {
  final OfflineAlbumGroup album;

  const LocalAlbumDetailScreen({super.key, required this.album});

  static String routeNameFor(String albumId) => '/library/local/album/$albumId';

  @override
  State<LocalAlbumDetailScreen> createState() => _LocalAlbumDetailScreenState();
}

class _LocalAlbumDetailScreenState extends BasePageState<LocalAlbumDetailScreen> {
  late final LocalAlbumDetailController _feature = bindController(
    LocalAlbumDetailController(AppScope.of(context), widget.album),
  );

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 16);

  Future<void> _removeDownloads(BuildContext context, List<Track> tracks, String label) async {
    if (tracks.isEmpty) {
      return;
    }

    final confirmed = await confirmRemoveDownloadedTracks(context, tracks, label: label);

    if (!confirmed || !context.mounted) {
      return;
    }

    await _feature.removeDownloads(tracks, label: label);

    if (mounted) {
      _feature.clearSelection();
    }
  }

  Widget _editTrackSelectionButton(VoidCallback? onPressed) {
    return Tooltip(
      message: 'Edit',
      child: ObsidianHudIconButton(iconWidget: const EditIcon(), onPressed: onPressed),
    );
  }

  Future<void> _playAlbum(AppController controller, OfflineAlbumGroup album) async {
    controller.updateShuffleMode(ShuffleMode.off, scope: ActionScope.local);
    await controller.playOfflineTrack(album.tracks.first.id, tracks: album.tracks);
  }

  Widget _localAlbumContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required PlaybackState playback,
    required String? playingId,
  }) {
    final album = _feature.currentAlbum(controller);
    final localAlbum = album.toAlbum();
    final selectedTracks = _feature.selectedTracks(album.tracks);

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
                    totalCount: album.tracks.length,
                    onCancel: _feature.clearSelection,
                    onSelectAll: () => _feature.selectAll(album.tracks),
                    onDeselectAll: _feature.deselectAll,
                    onRemove: selectedTracks.isEmpty
                        ? null
                        : () => _removeDownloads(context, selectedTracks, album.title),
                  ),
                ]
              : [_editTrackSelectionButton(album.tracks.isNotEmpty ? _feature.startSelection : null)],
        ),
      ),
      body: PageBody.slivers(
        slivers: [
          PageSliverBox(
            top: 0,
            bottom: 16,
            child: AlbumHero(
              album: localAlbum,
              coverUrl: album.coverPath ?? '',
              headers: const {},
              actions: BannerPlaybackButton(
                message: 'Play album',
                visible: !_feature.selectionMode,
                onPressed: album.tracks.isEmpty ? null : () => _playAlbum(controller, album),
              ),
            ),
          ),
          if (album.tracks.isEmpty)
            const PageSliverBox(
              top: 24,
              bottom: 0,
              child: EmptyStateText(
                title: 'No downloaded tracks',
                message: 'Downloaded tracks for this album appear here.',
              ),
            )
          else ...[
            PageSliverPadding(
              top: 0,
              bottom: 24,
              sliver: TrackSliverList(
                tracks: album.tracks,
                useAlbumTrackNumbers: true,
                actionsInMenu: true,
                isPlayingTrack: (track) => playback.isPlaying && playingId == track.id,
                onTrackTap: (track) => controller.playOfflineTrack(track.id, tracks: album.tracks),
                onTrackAddToPlaylist: (track) =>
                    showAddToPlaylistModalForTrack(context, track, scope: ActionScope.local),
                onTrackLike: controller.toggleLocalLike,
                selectionMode: _feature.selectionMode,
                isTrackSelected: (track) => _feature.selectedTrackIds.contains(_feature.selectionKey(track)),
                onTrackSelectionToggle: _feature.toggleSelection,
                onTrackSelectionModeRequested: _feature.enterSelection,
                offlineDownloadForTrack: (track) => _feature.offlineDownloadForTrack(controller, track),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<PlaybackState>(
      stream: controller.playbackStream,
      initialData: controller.playbackState,
      builder: (context, playbackSnapshot) {
        final playback = playbackSnapshot.data ?? controller.playbackState;
        final playingId = playback.track?.id;

        return StreamBuilder<List<OfflineTrackDownload>>(
          stream: controller.offlineDownloadsStream,
          initialData: controller.offlineDownloads,
          builder: (context, _) =>
              _localAlbumContent(context, assemble, controller, playback: playback, playingId: playingId),
        );
      },
    );
  }
}
