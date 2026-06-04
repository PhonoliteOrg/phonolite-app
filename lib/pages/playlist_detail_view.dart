import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/marquee_text.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/tech_button.dart';

class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({
    super.key,
    required this.playlistId,
    this.isLocal = false,
  });

  final String playlistId;
  final bool isLocal;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (widget.isLocal) {
      controller.loadLocalPlaylistTracks(widget.playlistId);
    } else {
      controller.loadPlaylistTracks(widget.playlistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<Playlist>>(
      stream: widget.isLocal
          ? controller.localPlaylistsStream
          : controller.playlistsStream,
      initialData: widget.isLocal
          ? controller.localPlaylists
          : controller.playlists,
      builder: (context, snapshot) {
        final playlist = (snapshot.data ?? []).firstWhere(
          (item) => item.id == widget.playlistId,
          orElse: () => Playlist(
            id: widget.playlistId,
            name: 'Playlist',
            trackIds: const [],
          ),
        );
        return Scaffold(
          backgroundColor: bgDark,
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: CommandLinkButton(
                    label: 'Back to playlists',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: _PlaylistBanner(
                    name: playlist.name,
                    onRename: () => _openRename(controller, playlist),
                    onDelete: () => _deletePlaylist(controller, playlist),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: StreamBuilder<List<Track>>(
                  stream: widget.isLocal
                      ? controller.localPlaylistTracksStream
                      : controller.playlistTracksStream,
                  initialData: widget.isLocal
                      ? controller.localPlaylistTracks
                      : controller.playlistTracks,
                  builder: (context, tracksSnapshot) {
                    final tracks = tracksSnapshot.data ?? [];
                    if (tracks.isEmpty) {
                      return SliverMainAxisGroup(
                        slivers: [
                          if (!_selectionMode)
                            _trackSelectionActionsSliver(enabled: false),
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: _EmptyPlaylistText()),
                          ),
                        ],
                      );
                    }
                    return StreamBuilder<PlaybackState>(
                      stream: controller.playbackStream,
                      initialData: controller.playbackState,
                      builder: (context, playbackSnapshot) {
                        final playback =
                            playbackSnapshot.data ?? controller.playbackState;
                        final playingId = playback.track?.id;
                        return StreamBuilder<List<OfflineTrackDownload>>(
                          stream: controller.offlineDownloadsStream,
                          initialData: controller.offlineDownloads,
                          builder: (context, _) {
                            final removableTracks = _removableTracks(
                              controller,
                              tracks,
                            );
                            final selectedTracks = _selectedTracks(
                              removableTracks,
                            );
                            return SliverMainAxisGroup(
                              slivers: [
                                _trackSelectionActionsSliver(
                                  enabled: removableTracks.isNotEmpty,
                                  selectedCount: selectedTracks.length,
                                  totalCount: removableTracks.length,
                                  onSelectAll: () =>
                                      _selectAll(removableTracks),
                                  onRemove: selectedTracks.isEmpty
                                      ? null
                                      : () => _removeDownloads(
                                          controller,
                                          selectedTracks,
                                          playlist.name,
                                        ),
                                ),
                                TrackSliverList(
                                  tracks: tracks,
                                  showAlbumArt: true,
                                  isPlayingTrack: (track) =>
                                      playback.isPlaying &&
                                      playingId == track.id,
                                  onTrackTap: (track) => widget.isLocal
                                      ? controller.queueLocalPlaylist(
                                          widget.playlistId,
                                          startTrackId: track.id,
                                        )
                                      : controller.queuePlaylist(
                                          widget.playlistId,
                                          startTrackId: track.id,
                                        ),
                                  onTrackAddToPlaylist: (track) =>
                                      showAddToPlaylistModalForTrack(
                                        context,
                                        track,
                                      ),
                                  onTrackDownload: widget.isLocal
                                      ? null
                                      : controller.downloadTrack,
                                  onTrackLike: widget.isLocal
                                      ? controller.toggleLocalLike
                                      : controller.toggleLike,
                                  onTrackDelete: (track) =>
                                      _removeTrack(controller, playlist, track),
                                  selectionMode: _selectionMode,
                                  canSelectTrack: (track) =>
                                      _canRemoveTrack(controller, track),
                                  isTrackSelected: (track) => _selectedTrackIds
                                      .contains(_selectionKey(track)),
                                  onTrackSelectionToggle: (track) =>
                                      _toggleSelection(controller, track),
                                  onTrackSelectionModeRequested: (track) =>
                                      _enterSelection(controller, track),
                                  offlineDownloadForTrack: (track) => controller
                                      .offlineDownloadForTrack(track.id),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openRename(AppController controller, Playlist playlist) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Rename playlist',
        initialValue: playlist.name,
        onSubmit: (value) => widget.isLocal
            ? controller.renameLocalPlaylist(playlist.id, value)
            : controller.renamePlaylist(playlist.id, value),
      ),
    );
  }

  Widget _trackSelectionActionsSliver({
    required bool enabled,
    int selectedCount = 0,
    int totalCount = 0,
    VoidCallback? onSelectAll,
    VoidCallback? onRemove,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: _selectionMode
              ? DownloadSelectionToolbar(
                  selectedCount: selectedCount,
                  totalCount: totalCount,
                  onCancel: _clearSelection,
                  onSelectAll: onSelectAll ?? () {},
                  onDeselectAll: _deselectAll,
                  onRemove: onRemove,
                )
              : Tooltip(
                  message: 'Edit',
                  child: ObsidianHudIconButton(
                    icon: Icons.edit_rounded,
                    onPressed: enabled ? _startSelection : null,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _removeTrack(
    AppController controller,
    Playlist playlist,
    Track track,
  ) async {
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Remove song from playlist',
      message: 'Are you sure you want to remove this song from this playlist?',
    );
    if (!confirmed) {
      return;
    }
    if (widget.isLocal) {
      await controller.removeTrackFromLocalPlaylist(playlist, track);
    } else {
      await controller.removeTrackFromPlaylist(playlist, track);
    }
  }

  Future<void> _removeDownloads(
    AppController controller,
    List<Track> tracks,
    String label,
  ) async {
    if (tracks.isEmpty) {
      return;
    }
    final confirmed = await confirmRemoveDownloadedTracks(
      context,
      tracks,
      label: label,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await controller.removeDownloadedTracks(tracks, label: label);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _deletePlaylist(
    AppController controller,
    Playlist playlist,
  ) async {
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Delete playlist',
      message: 'Are you sure you want to delete this playlist?',
    );
    if (!confirmed) {
      return;
    }
    if (widget.isLocal) {
      await controller.deleteLocalPlaylist(playlist.id);
    } else {
      await controller.deletePlaylist(playlist.id);
    }
    if (!mounted) {
      return;
    }
    final source = widget.isLocal
        ? controller.localPlaylists
        : controller.playlists;
    final wasDeleted = source.every((item) => item.id != playlist.id);
    if (wasDeleted) {
      Navigator.of(context).pop();
    }
  }

  List<Track> _removableTracks(AppController controller, List<Track> tracks) {
    return tracks
        .where((track) => _canRemoveTrack(controller, track))
        .toList(growable: false);
  }

  List<Track> _selectedTracks(List<Track> tracks) {
    return tracks
        .where((track) => _selectedTrackIds.contains(_selectionKey(track)))
        .toList(growable: false);
  }

  bool _canRemoveTrack(AppController controller, Track track) {
    return controller.availableOfflineDownloadForTrack(track.id) != null;
  }

  void _enterSelection(AppController controller, Track track) {
    if (!_canRemoveTrack(controller, track)) {
      return;
    }
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.add(_selectionKey(track));
    });
  }

  void _toggleSelection(AppController controller, Track track) {
    if (!_canRemoveTrack(controller, track)) {
      return;
    }
    final key = _selectionKey(track);
    setState(() {
      _selectionMode = true;
      if (!_selectedTrackIds.remove(key)) {
        _selectedTrackIds.add(key);
      }
    });
  }

  void _selectAll(List<Track> tracks) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds
        ..clear()
        ..addAll(tracks.map(_selectionKey));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.clear();
    });
  }

  void _startSelection() {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  String _selectionKey(Track track) {
    return track.localId ?? track.serverTrackId ?? track.id;
  }
}

class _PlaylistBanner extends StatelessWidget {
  const _PlaylistBanner({
    required this.name,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final nameStyle = GoogleFonts.rajdhani(
          fontSize: isCompact ? 40 : 60,
          fontWeight: FontWeight.w700,
          height: 0.95,
          letterSpacing: 1.6,
        );
        final renameButton = TechButton(
          label: 'Rename',
          icon: Icons.edit,
          onTap: onRename,
          density: isCompact
              ? TechButtonDensity.compact
              : TechButtonDensity.standard,
        );
        final deleteButton = TechButton(
          label: 'Delete',
          icon: Icons.delete,
          onTap: onDelete,
          variant: TechButtonVariant.danger,
          density: isCompact
              ? TechButtonDensity.compact
              : TechButtonDensity.standard,
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(
                text: name.toUpperCase(),
                style: nameStyle,
                velocity: 28,
                gap: 32,
                pause: const Duration(milliseconds: 900),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [renameButton, deleteButton],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(name.toUpperCase(), style: nameStyle)),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [renameButton, const SizedBox(width: 10), deleteButton],
            ),
          ],
        );
      },
    );
  }
}

class _EmptyPlaylistText extends StatelessWidget {
  const _EmptyPlaylistText();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No tracks yet.',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: ObsidianPalette.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
