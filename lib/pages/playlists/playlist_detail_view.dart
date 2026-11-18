import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlist_detail_controller.dart';
import 'package:phonolite_app/data/models/collections/local_playlist_entry.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/album.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/remove_download_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/add_to_playlist_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/empty_playlist_text.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/playlist_edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/loading_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/music/albums/album_hero.dart';
import 'package:phonolite_app/ui/shared/music/banner_playback_button.dart';
import 'package:phonolite_app/ui/shared/music/tracks/track_sliver_list.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/page_sliver_box.dart';
import 'package:phonolite_app/ui/shell/page_sliver_padding.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class PlaylistDetailView extends BasePage {
  final String playlistId;
  final bool isLocal;

  const PlaylistDetailView({super.key, required this.playlistId, this.isLocal = false});

  static String routeNameFor(String playlistId, {required bool isLocal}) =>
      '/playlists/${isLocal ? 'local' : 'server'}/playlist/$playlistId';

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends BasePageState<PlaylistDetailView> {
  late final PlaylistDetailController _feature = bindController(
    PlaylistDetailController(AppScope.of(context), widget.playlistId, widget.isLocal),
  );

  @override
  bool get usesScaffold => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.fromLTRB(20, 16, 20, 16);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _feature.loadTracksIfNeeded(AppScope.of(context));
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.playlistId != widget.playlistId || oldWidget.isLocal != widget.isLocal) {
      _feature.setPlaylist(widget.playlistId, widget.isLocal);
    }
  }

  Widget _playlistPlaybackButton(List<Track> tracks) {
    return BannerPlaybackButton(
      message: 'Play playlist',
      visible: !_feature.selectionMode,
      onPressed: _feature.tracksLoading || !tracks.any(_feature.isTrackPlayable) ? null : _feature.playFromTop,
    );
  }

  Future<void> _openRename(AppController controller, Playlist playlist) {
    return showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Rename playlist',
        initialValue: playlist.name,
        initialDescription: playlist.description ?? '',
        initialImageUrl: _feature.coverUrl(playlist),
        onSubmit: (value, description, imageEdit, _) =>
            _feature.rename(value, description: description, imageEdit: imageEdit),
      ),
    );
  }

  Future<void> _openDownload(AppController controller, Playlist playlist, List<Track> tracks) {
    return showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Download playlist',
        initialValue: playlist.name,
        initialDescription: playlist.description ?? '',
        initialImageUrl: _feature.serverPlaylistCoverUrl(controller, playlist),
        onSubmit: (value, description, imageEdit, _) =>
            controller.downloadPlaylist(playlist, tracks, name: value, description: description, imageEdit: imageEdit),
      ),
    );
  }

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

  Widget _playlistContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required Playlist playlist,
    required String playlistCoverUrl,
    required Album playlistAlbum,
    required List<Track> displayedTracks,
  }) {
    final removableTracks = _feature.removableTracks(controller, displayedTracks);
    final selectedTracks = _feature.selectedTracks(removableTracks);

    return assemble(
      context,
      navbar: DetailActionHeader(
        backLabel: 'Back to playlists',
        onBack: () => Navigator.of(context).pop(),
        actions: _feature.selectionMode
            ? DownloadSelectionToolbar(
                selectedCount: selectedTracks.length,
                totalCount: removableTracks.length,
                onCancel: _feature.clearSelection,
                onSelectAll: () => _feature.selectAll(removableTracks),
                onDeselectAll: _feature.deselectAll,
                onRemove: selectedTracks.isEmpty ? null : () => _removeDownloads(selectedTracks, playlist.name),
              )
            : PageToolbarActions(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!widget.isLocal)
                    TechButton(
                      label: 'Download playlist',
                      icon: PhonoliteIcons.download,
                      iconOnly: isCompactListWidth(context),
                      tooltip: 'Download playlist',
                      onTap: _feature.tracksLoading || displayedTracks.isEmpty
                          ? null
                          : () => _openDownload(controller, playlist, List.unmodifiable(displayedTracks)),
                    ),
                  Tooltip(
                    message: 'Edit details',
                    excludeFromSemantics: true,
                    child: ObsidianHudIconButton(
                      semanticLabel: 'Edit details',
                      iconWidget: const EditIcon(),
                      onPressed: () => _openRename(controller, playlist),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit tracks',
                    excludeFromSemantics: true,
                    child: ObsidianHudIconButton(
                      semanticLabel: 'Edit tracks',
                      iconWidget: const PlaylistEditIcon(),
                      onPressed: removableTracks.isEmpty ? null : _feature.startSelection,
                    ),
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
              album: playlistAlbum,
              coverUrl: playlistCoverUrl,
              actions: _playlistPlaybackButton(displayedTracks),
            ),
          ),
          if (_feature.tracksLoading)
            loadingSliver()
          else if (displayedTracks.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: EmptyPlaylistText()))
          else
            PageSliverPadding(
              top: 0,
              bottom: 24,
              sliver: StreamBuilder<PlaybackState>(
                stream: controller.playbackStream,
                initialData: controller.playbackState,
                builder: (context, playbackSnapshot) {
                  final playback = playbackSnapshot.data ?? controller.playbackState;
                  final playingId = playback.track?.id;

                  return TrackSliverList(
                    tracks: displayedTracks,
                    showAlbumArt: true,
                    isPlayingTrack: (track) => playback.isPlaying && playingId == track.id,
                    onTrackTap: _feature.playFrom,
                    onTrackAddToPlaylist: (track) =>
                        showAddToPlaylistModalForTrack(context, track, scope: _feature.actionScope),
                    onTrackDownload: widget.isLocal ? null : controller.downloadTrack,
                    onTrackRetryDownload: widget.isLocal ? _feature.retryTrackDownload : null,
                    onTrackContinueDownload: widget.isLocal ? _feature.continueTrackDownload : null,
                    downloadStatusForTrack: widget.isLocal ? _feature.downloadStatusForTrack : null,
                    isTrackPlayable: _feature.isTrackPlayable,
                    onTrackLike: _feature.toggleLike,
                    selectionMode: _feature.selectionMode,
                    canSelectTrack: (track) => _feature.canRemoveTrack(controller, track),
                    isTrackSelected: (track) => _feature.selectedTrackIds.contains(_feature.selectionKey(track)),
                    onTrackSelectionToggle: (track) => _feature.toggleSelection(controller, track),
                    onTrackSelectionModeRequested: (track) => _feature.enterSelection(controller, track),
                    offlineDownloadForTrack: _feature.offlineDownloadForTrack,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final controller = AppScope.of(context);

    return StreamBuilder<List<Playlist>>(
      stream: widget.isLocal ? controller.localPlaylistsStream : controller.playlistsStream,
      initialData: widget.isLocal ? controller.localPlaylists : controller.playlists,
      builder: (context, snapshot) {
        if (_feature.playlistDeleted) {
          return assemble(
            context,
            navbar: DetailActionHeader(backLabel: 'Back to playlists', onBack: () => Navigator.of(context).pop()),
            body: const PageBody.slivers(
              slivers: [
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('This playlist was deleted.'))),
              ],
            ),
          );
        }

        final playlist = _feature.playlistFrom(snapshot.data ?? const <Playlist>[]);
        final playlistCoverUrl = _feature.coverUrl(playlist) ?? '';
        final playlistAlbum = _feature.playlistAlbum(playlist);

        if (widget.isLocal) {
          return StreamBuilder<List<LocalPlaylistEntry>>(
            stream: controller.localPlaylistEntriesStream,
            initialData: controller.localPlaylistEntries,
            builder: (context, entriesSnapshot) {
              final entries = _feature.entriesFrom(entriesSnapshot.data ?? const <LocalPlaylistEntry>[]);
              final tracks = entries.map((entry) => entry.track).toList(growable: false);

              return StreamBuilder<List<OfflineTrackDownload>>(
                stream: controller.offlineDownloadsStream,
                initialData: controller.offlineDownloads,
                builder: (context, _) => _playlistContent(
                  context,
                  assemble,
                  controller,
                  playlist: playlist,
                  playlistCoverUrl: playlistCoverUrl,
                  playlistAlbum: playlistAlbum,
                  displayedTracks: _feature.displayedTracks(tracks),
                ),
              );
            },
          );
        }

        return StreamBuilder<List<Track>>(
          stream: controller.playlistTracksStream,
          initialData: controller.playlistTracks,
          builder: (context, tracksSnapshot) {
            final displayedTracks = _feature.displayedTracks(tracksSnapshot.data ?? const <Track>[]);

            return StreamBuilder<List<OfflineTrackDownload>>(
              stream: controller.offlineDownloadsStream,
              initialData: controller.offlineDownloads,
              builder: (context, _) => _playlistContent(
                context,
                assemble,
                controller,
                playlist: playlist,
                playlistCoverUrl: playlistCoverUrl,
                playlistAlbum: playlistAlbum,
                displayedTracks: displayedTracks,
              ),
            );
          },
        );
      },
    );
  }
}
