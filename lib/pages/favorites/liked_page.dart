import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/favorites/liked_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/favorites/widgets/liked_section.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_edit_icon.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class LikedPage extends BasePage {
  const LikedPage({super.key});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends BasePageState<LikedPage> {
  late final LikedController _feature = bindController(LikedController(AppScope.of(context)));

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

  double _headerActionIconSize(BuildContext context) => PageToolbarActionLayout.of(context).iconSize;

  Widget _trackSection(
    BuildContext context,
    AppController controller, {
    required List<Track> tracks,
    required PlaybackState playback,
    required ActionScope scope,
    required String? title,
    required String emptyTitle,
  }) {
    final local = scope == ActionScope.local;

    return LikedSection(
      title: title,
      tracks: tracks,
      emptyTitle: emptyTitle,
      playback: playback,
      onTap: local
          ? (track) => controller.playLocalLikedTrack(track.id)
          : (track) => controller.playLikedTrack(track.id),
      onLike: local ? controller.toggleLocalLike : controller.toggleLike,
      onAddToPlaylist: (track) => showAddToPlaylistModalForTrack(context, track, scope: scope),
      onDownload: local ? null : controller.downloadTrack,
      offlineDownloadForTrack: (track) => controller.offlineDownloadForTrack(track.id),
      selectionMode: _feature.selectionMode,
      canSelectTrack: (track) => _feature.canRemoveTrack(controller, track),
      isTrackSelected: (track) => (local ? _feature.selectedLocalTrackIds : _feature.selectedServerTrackIds).contains(
        _feature.selectionKey(track),
      ),
      onSelectionToggle: (track) => _feature.toggleSelection(controller, track, local: local),
      onSelectionModeRequested: (track) => _feature.enterSelection(controller, track, local: local),
    );
  }

  Widget _likedContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AuthState authState,
    required List<Track> localTracks,
    required List<Track> serverTracks,
    required PlaybackState playback,
  }) {
    final localRemovableTracks = _feature.removableTracks(controller, localTracks);
    final serverRemovableTracks = _feature.removableTracks(controller, serverTracks);
    final selectedLocalTracks = _feature.selectedTracks(localRemovableTracks, _feature.selectedLocalTrackIds);
    final selectedServerTracks = _feature.selectedTracks(serverRemovableTracks, _feature.selectedServerTrackIds);
    final selectedTracks = <Track>[...selectedLocalTracks, ...selectedServerTracks];
    final removableCount = localRemovableTracks.length + serverRemovableTracks.length;

    return assemble(
      context,
      navbar: LibraryHeader(
        title: 'LIKED TRACKS',
        trailing: _feature.selectionMode
            ? DownloadSelectionToolbar(
                selectedCount: selectedTracks.length,
                totalCount: removableCount,
                onCancel: _feature.clearSelection,
                onSelectAll: () =>
                    _feature.selectAll(localTracks: localRemovableTracks, serverTracks: serverRemovableTracks),
                onDeselectAll: _feature.deselectAll,
                onRemove: selectedTracks.isEmpty ? null : () => _removeDownloads(selectedTracks, 'liked tracks'),
              )
            : Tooltip(
                message: 'Edit tracks',
                child: ObsidianHudIconButton(
                  iconWidget: const PlaylistEditIcon(),
                  size: _headerActionIconSize(context),
                  onPressed: removableCount > 0 ? _feature.startSelection : null,
                ),
              ),
      ),
      body: PageBody.slivers(
        slivers: [
          _trackSection(
            context,
            controller,
            tracks: localTracks,
            playback: playback,
            scope: ActionScope.local,
            title: authState.isAuthorized ? 'Local Liked Tracks' : null,
            emptyTitle: authState.isAuthorized ? 'No local liked tracks' : 'No liked tracks',
          ),
          if (authState.isAuthorized)
            _trackSection(
              context,
              controller,
              tracks: serverTracks,
              playback: playback,
              scope: ActionScope.server,
              title: 'Server Liked Tracks',
              emptyTitle: 'No server liked tracks',
            ),
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final authState = authSnapshot.data ?? controller.authState;

        return StreamBuilder<List<Track>>(
          stream: controller.localLikedStream,
          initialData: controller.localLiked,
          builder: (context, localSnapshot) {
            final localTracks = localSnapshot.data ?? const <Track>[];

            return StreamBuilder<List<Track>>(
              stream: controller.likedStream,
              initialData: controller.liked,
              builder: (context, serverSnapshot) {
                final serverTracks = authState.isAuthorized ? serverSnapshot.data ?? const <Track>[] : const <Track>[];

                return StreamBuilder<PlaybackState>(
                  stream: controller.playbackStream,
                  initialData: controller.playbackState,
                  builder: (context, playbackSnapshot) {
                    final playback = playbackSnapshot.data ?? controller.playbackState;

                    return StreamBuilder<List<OfflineTrackDownload>>(
                      stream: controller.offlineDownloadsStream,
                      initialData: controller.offlineDownloads,
                      builder: (context, _) {
                        return _likedContent(
                          context,
                          assemble,
                          controller,
                          authState: authState,
                          localTracks: localTracks,
                          serverTracks: serverTracks,
                          playback: playback,
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
  }
}
