import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/track_row_tile.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';

class LikedPage extends StatefulWidget {
  const LikedPage({super.key});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  bool _requestedLocalLoad = false;
  bool _requestedServerLoad = false;
  bool _selectionMode = false;
  final Set<String> _selectedLocalTrackIds = <String>{};
  final Set<String> _selectedServerTrackIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (!_requestedLocalLoad) {
      _requestedLocalLoad = true;
      controller.loadLocalLikedTracks();
    }
    if (controller.authState.isAuthorized &&
        !_requestedServerLoad &&
        controller.liked.isEmpty) {
      _requestedServerLoad = true;
      controller.loadLikedTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<AuthState>(
      stream: controller.authStream,
      initialData: controller.authState,
      builder: (context, authSnapshot) {
        final authState = authSnapshot.data ?? controller.authState;
        if (authState.isAuthorized &&
            !_requestedServerLoad &&
            controller.liked.isEmpty) {
          _requestedServerLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.authState.isAuthorized) {
              controller.loadLikedTracks();
            }
          });
        }
        return StreamBuilder<List<Track>>(
          stream: controller.localLikedStream,
          initialData: controller.localLiked,
          builder: (context, localSnapshot) {
            final localTracks = localSnapshot.data ?? const <Track>[];
            return StreamBuilder<List<Track>>(
              stream: controller.likedStream,
              initialData: controller.liked,
              builder: (context, serverSnapshot) {
                final serverTracks = authState.isAuthorized
                    ? serverSnapshot.data ?? const <Track>[]
                    : const <Track>[];
                return StreamBuilder<PlaybackState>(
                  stream: controller.playbackStream,
                  initialData: controller.playbackState,
                  builder: (context, playbackSnapshot) {
                    final playback =
                        playbackSnapshot.data ?? controller.playbackState;
                    return StreamBuilder<List<OfflineTrackDownload>>(
                      stream: controller.offlineDownloadsStream,
                      initialData: controller.offlineDownloads,
                      builder: (context, _) {
                        final localRemovableTracks = _removableTracks(
                          controller,
                          localTracks,
                        );
                        final serverRemovableTracks = _removableTracks(
                          controller,
                          serverTracks,
                        );
                        final selectedLocalTracks = _selectedTracks(
                          localRemovableTracks,
                          _selectedLocalTrackIds,
                        );
                        final selectedServerTracks = _selectedTracks(
                          serverRemovableTracks,
                          _selectedServerTrackIds,
                        );
                        final selectedTracks = <Track>[
                          ...selectedLocalTracks,
                          ...selectedServerTracks,
                        ];
                        final removableCount =
                            localRemovableTracks.length +
                            serverRemovableTracks.length;
                        return CustomScrollView(
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
                                  title: 'LIKED TRACKS',
                                  moduleCount: 0,
                                  trailing: _selectionMode
                                      ? DownloadSelectionToolbar(
                                          selectedCount: selectedTracks.length,
                                          totalCount: removableCount,
                                          onCancel: _clearSelection,
                                          onSelectAll: () => _selectAll(
                                            localTracks: localRemovableTracks,
                                            serverTracks: serverRemovableTracks,
                                          ),
                                          onDeselectAll: _deselectAll,
                                          onRemove: selectedTracks.isEmpty
                                              ? null
                                              : () => _removeDownloads(
                                                  controller,
                                                  selectedTracks,
                                                  'liked tracks',
                                                ),
                                        )
                                      : Tooltip(
                                          message: 'Edit',
                                          child: ObsidianHudIconButton(
                                            icon: Icons.edit_rounded,
                                            onPressed: removableCount > 0
                                                ? _startSelection
                                                : null,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            _LikedSection(
                              title: 'Local Liked Tracks',
                              tracks: localTracks,
                              emptyTitle: 'No local liked tracks',
                              playback: playback,
                              onTap: (track) =>
                                  controller.playLocalLikedTrack(track.id),
                              onLike: controller.toggleLocalLike,
                              onAddToPlaylist: (track) =>
                                  showAddToPlaylistModalForTrack(
                                    context,
                                    track,
                                    scope: ActionScope.local,
                                  ),
                              offlineDownloadForTrack: (track) =>
                                  controller.offlineDownloadForTrack(track.id),
                              selectionMode: _selectionMode,
                              canSelectTrack: (track) =>
                                  _canRemoveTrack(controller, track),
                              isTrackSelected: (track) => _selectedLocalTrackIds
                                  .contains(_selectionKey(track)),
                              onSelectionToggle: (track) => _toggleSelection(
                                controller,
                                track,
                                local: true,
                              ),
                              onSelectionModeRequested: (track) =>
                                  _enterSelection(
                                    controller,
                                    track,
                                    local: true,
                                  ),
                            ),
                            if (authState.isAuthorized)
                              _LikedSection(
                                title: 'Server Liked Tracks',
                                tracks: serverTracks,
                                emptyTitle: 'No server liked tracks',
                                playback: playback,
                                onTap: (track) =>
                                    controller.playLikedTrack(track.id),
                                onLike: controller.toggleLike,
                                onAddToPlaylist: (track) =>
                                    showAddToPlaylistModalForTrack(
                                      context,
                                      track,
                                      scope: ActionScope.server,
                                    ),
                                onDownload: controller.downloadTrack,
                                offlineDownloadForTrack: (track) => controller
                                    .offlineDownloadForTrack(track.id),
                                selectionMode: _selectionMode,
                                canSelectTrack: (track) =>
                                    _canRemoveTrack(controller, track),
                                isTrackSelected: (track) =>
                                    _selectedServerTrackIds.contains(
                                      _selectionKey(track),
                                    ),
                                onSelectionToggle: (track) => _toggleSelection(
                                  controller,
                                  track,
                                  local: false,
                                ),
                                onSelectionModeRequested: (track) =>
                                    _enterSelection(
                                      controller,
                                      track,
                                      local: false,
                                    ),
                              ),
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

  List<Track> _removableTracks(AppController controller, List<Track> tracks) {
    return tracks
        .where((track) => _canRemoveTrack(controller, track))
        .toList(growable: false);
  }

  List<Track> _selectedTracks(List<Track> tracks, Set<String> selectedIds) {
    return tracks
        .where((track) => selectedIds.contains(_selectionKey(track)))
        .toList(growable: false);
  }

  bool _canRemoveTrack(AppController controller, Track track) {
    return controller.availableOfflineDownloadForTrack(track.id) != null;
  }

  void _startSelection() {
    setState(() {
      _selectionMode = true;
      _selectedLocalTrackIds.clear();
      _selectedServerTrackIds.clear();
    });
  }

  void _enterSelection(
    AppController controller,
    Track track, {
    required bool local,
  }) {
    if (!_canRemoveTrack(controller, track)) {
      return;
    }
    final selectedIds = local
        ? _selectedLocalTrackIds
        : _selectedServerTrackIds;
    setState(() {
      _selectionMode = true;
      selectedIds.add(_selectionKey(track));
    });
  }

  void _toggleSelection(
    AppController controller,
    Track track, {
    required bool local,
  }) {
    if (!_canRemoveTrack(controller, track)) {
      return;
    }
    final key = _selectionKey(track);
    final selectedIds = local
        ? _selectedLocalTrackIds
        : _selectedServerTrackIds;
    setState(() {
      _selectionMode = true;
      if (!selectedIds.remove(key)) {
        selectedIds.add(key);
      }
    });
  }

  void _selectAll({
    required List<Track> localTracks,
    required List<Track> serverTracks,
  }) {
    setState(() {
      _selectionMode = true;
      _selectedLocalTrackIds
        ..clear()
        ..addAll(localTracks.map(_selectionKey));
      _selectedServerTrackIds
        ..clear()
        ..addAll(serverTracks.map(_selectionKey));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectionMode = true;
      _selectedLocalTrackIds.clear();
      _selectedServerTrackIds.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedLocalTrackIds.clear();
      _selectedServerTrackIds.clear();
    });
  }

  String _selectionKey(Track track) {
    return track.localId ?? track.serverTrackId ?? track.id;
  }
}

class _LikedSection extends StatelessWidget {
  const _LikedSection({
    required this.title,
    required this.tracks,
    required this.emptyTitle,
    required this.playback,
    required this.onTap,
    required this.onLike,
    required this.onAddToPlaylist,
    required this.offlineDownloadForTrack,
    required this.selectionMode,
    required this.canSelectTrack,
    required this.isTrackSelected,
    required this.onSelectionToggle,
    required this.onSelectionModeRequested,
    this.onDownload,
  });

  final String title;
  final List<Track> tracks;
  final String emptyTitle;
  final PlaybackState playback;
  final ValueChanged<Track> onTap;
  final ValueChanged<Track> onLike;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track>? onDownload;
  final OfflineTrackDownload? Function(Track track) offlineDownloadForTrack;
  final bool selectionMode;
  final bool Function(Track track) canSelectTrack;
  final bool Function(Track track) isTrackSelected;
  final ValueChanged<Track> onSelectionToggle;
  final ValueChanged<Track> onSelectionModeRequested;

  @override
  Widget build(BuildContext context) {
    final playingId = playback.track?.id;
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(
            child: ObsidianSectionHeader(title: title),
          ),
        ),
        if (tracks.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverToBoxAdapter(
              child: _LikedEmptyText(title: emptyTitle),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackRowTile(
                  track: track,
                  index: index + 1,
                  showAlbumArt: true,
                  isPlaying: playback.isPlaying && playingId == track.id,
                  onTap: () => onTap(track),
                  onAddToPlaylist: () => onAddToPlaylist(track),
                  onDownload: onDownload == null
                      ? null
                      : () => onDownload!(track),
                  onLike: () => onLike(track),
                  selectionMode: selectionMode,
                  selected: isTrackSelected(track),
                  onSelectionToggle: canSelectTrack(track)
                      ? () => onSelectionToggle(track)
                      : null,
                  onSelectionModeRequested: canSelectTrack(track)
                      ? () => onSelectionModeRequested(track)
                      : null,
                  offlineDownload: offlineDownloadForTrack(track),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _LikedEmptyText extends StatelessWidget {
  const _LikedEmptyText({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: ObsidianPalette.textMuted,
            letterSpacing: 0.6,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
