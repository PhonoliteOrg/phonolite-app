import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/empty_state.dart';
import '../widgets/display/track_row_tile.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/tech_button.dart';

class LikedPage extends StatefulWidget {
  const LikedPage({super.key});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  bool _requestedLocalLoad = false;
  bool _requestedServerLoad = false;
  bool _localSelectionMode = false;
  bool _serverSelectionMode = false;
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
                        return CustomScrollView(
                          slivers: [
                            _LikedSection(
                              title: 'Local Liked Downloads',
                              tracks: localTracks,
                              emptyTitle: 'No local liked downloads',
                              emptyMessage:
                                  'Downloaded tracks you like locally will appear here.',
                              playback: playback,
                              onTap: (track) =>
                                  controller.playLocalLikedTrack(track.id),
                              onLike: controller.toggleLocalLike,
                              onAddToPlaylist: (track) =>
                                  showAddToPlaylistModalForTrack(
                                    context,
                                    track,
                                  ),
                              offlineDownloadForTrack: (track) =>
                                  controller.offlineDownloadForTrack(track.id),
                              selectionMode: _localSelectionMode,
                              selectedCount: selectedLocalTracks.length,
                              removableCount: localRemovableTracks.length,
                              onStartSelection: () =>
                                  _startSelection(local: true),
                              onCancelSelection: () =>
                                  _clearSelection(local: true),
                              onSelectAll: () => _selectAll(
                                local: true,
                                tracks: localRemovableTracks,
                              ),
                              onRemoveSelected: selectedLocalTracks.isEmpty
                                  ? null
                                  : () => _removeDownloads(
                                      controller,
                                      selectedLocalTracks,
                                      'local liked downloads',
                                      local: true,
                                    ),
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
                                title: 'Connected Server Liked Songs',
                                tracks: serverTracks,
                                emptyTitle: 'No server liked tracks',
                                emptyMessage:
                                    'Tap the heart icon on a server track to like it on this server.',
                                playback: playback,
                                onTap: (track) =>
                                    controller.playLikedTrack(track.id),
                                onLike: controller.toggleLike,
                                onAddToPlaylist: (track) =>
                                    showAddToPlaylistModalForTrack(
                                      context,
                                      track,
                                    ),
                                onDownload: controller.downloadTrack,
                                offlineDownloadForTrack: (track) => controller
                                    .offlineDownloadForTrack(track.id),
                                selectionMode: _serverSelectionMode,
                                selectedCount: selectedServerTracks.length,
                                removableCount: serverRemovableTracks.length,
                                onStartSelection: () =>
                                    _startSelection(local: false),
                                onCancelSelection: () =>
                                    _clearSelection(local: false),
                                onSelectAll: () => _selectAll(
                                  local: false,
                                  tracks: serverRemovableTracks,
                                ),
                                onRemoveSelected: selectedServerTracks.isEmpty
                                    ? null
                                    : () => _removeDownloads(
                                        controller,
                                        selectedServerTracks,
                                        'connected liked songs',
                                        local: false,
                                      ),
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
    String label, {
    required bool local,
  }) async {
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
      _clearSelection(local: local);
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

  void _startSelection({required bool local}) {
    setState(() {
      if (local) {
        _localSelectionMode = true;
        _selectedLocalTrackIds.clear();
      } else {
        _serverSelectionMode = true;
        _selectedServerTrackIds.clear();
      }
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
      if (local) {
        _localSelectionMode = true;
      } else {
        _serverSelectionMode = true;
      }
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
      if (local) {
        _localSelectionMode = true;
      } else {
        _serverSelectionMode = true;
      }
      if (!selectedIds.remove(key)) {
        selectedIds.add(key);
      }
    });
  }

  void _selectAll({required bool local, required List<Track> tracks}) {
    final selectedIds = local
        ? _selectedLocalTrackIds
        : _selectedServerTrackIds;
    setState(() {
      if (local) {
        _localSelectionMode = true;
      } else {
        _serverSelectionMode = true;
      }
      selectedIds
        ..clear()
        ..addAll(tracks.map(_selectionKey));
    });
  }

  void _clearSelection({required bool local}) {
    setState(() {
      if (local) {
        _localSelectionMode = false;
        _selectedLocalTrackIds.clear();
      } else {
        _serverSelectionMode = false;
        _selectedServerTrackIds.clear();
      }
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
    required this.emptyMessage,
    required this.playback,
    required this.onTap,
    required this.onLike,
    required this.onAddToPlaylist,
    required this.offlineDownloadForTrack,
    required this.selectionMode,
    required this.selectedCount,
    required this.removableCount,
    required this.onStartSelection,
    required this.onCancelSelection,
    required this.onSelectAll,
    required this.onRemoveSelected,
    required this.canSelectTrack,
    required this.isTrackSelected,
    required this.onSelectionToggle,
    required this.onSelectionModeRequested,
    this.onDownload,
  });

  final String title;
  final List<Track> tracks;
  final String emptyTitle;
  final String emptyMessage;
  final PlaybackState playback;
  final ValueChanged<Track> onTap;
  final ValueChanged<Track> onLike;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track>? onDownload;
  final OfflineTrackDownload? Function(Track track) offlineDownloadForTrack;
  final bool selectionMode;
  final int selectedCount;
  final int removableCount;
  final VoidCallback onStartSelection;
  final VoidCallback onCancelSelection;
  final VoidCallback onSelectAll;
  final VoidCallback? onRemoveSelected;
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
            child: _buildHeader(context, tracks.length),
          ),
        ),
        if (selectionMode)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: DownloadSelectionToolbar(
                selectedCount: selectedCount,
                totalCount: removableCount,
                onCancel: onCancelSelection,
                onSelectAll: onSelectAll,
                onRemove: onRemoveSelected,
              ),
            ),
          ),
        if (tracks.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverToBoxAdapter(
              child: EmptyStateText(title: emptyTitle, message: emptyMessage),
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

  Widget _buildHeader(BuildContext context, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.favorite_rounded, size: 42),
        const SizedBox(width: 20),
        Expanded(
          child: ObsidianSectionHeader(title: title, subtitle: '$count tracks'),
        ),
        if (!selectionMode)
          TechButton(
            label: 'Edit',
            icon: Icons.edit_rounded,
            onTap: removableCount > 0 ? onStartSelection : null,
          ),
      ],
    );
  }
}
