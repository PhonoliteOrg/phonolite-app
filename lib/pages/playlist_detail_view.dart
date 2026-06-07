import 'dart:async';

import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../entities/offline_library.dart';
import '../widgets/display/album_hero.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/display/track_sliver_list.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/modals/add_to_playlist_modal.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/modals/remove_download_modal.dart';
import '../widgets/modal/loading_widgets.dart';
import '../widgets/navigation/detail_action_header.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/obsidian_theme.dart';

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
  bool _tracksLoading = true;
  String? _activeTracksLoadKey;
  int _tracksLoadRequestId = 0;
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTracksIfNeeded(AppScope.of(context));
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId ||
        oldWidget.isLocal != widget.isLocal) {
      _loadTracksIfNeeded(AppScope.of(context), force: true);
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
        final playlistCoverUrl = widget.isLocal
            ? playlist.imagePath ?? ''
            : _serverPlaylistCoverUrl(controller, playlist) ?? '';
        final playlistAlbum = _playlistAlbum(playlist);
        final playlistHeaders = widget.isLocal
            ? const <String, String>{}
            : authHeaders(controller);
        return StreamBuilder<List<Track>>(
          stream: widget.isLocal
              ? controller.localPlaylistTracksStream
              : controller.playlistTracksStream,
          initialData: widget.isLocal
              ? controller.localPlaylistTracks
              : controller.playlistTracks,
          builder: (context, tracksSnapshot) {
            final tracks = tracksSnapshot.data ?? [];
            final displayedTracks = _tracksLoading ? const <Track>[] : tracks;
            return StreamBuilder<List<OfflineTrackDownload>>(
              stream: controller.offlineDownloadsStream,
              initialData: controller.offlineDownloads,
              builder: (context, _) {
                final removableTracks = _removableTracks(
                  controller,
                  displayedTracks,
                );
                final selectedTracks = _selectedTracks(removableTracks);
                return Scaffold(
                  backgroundColor: bgDark,
                  body: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        sliver: SliverToBoxAdapter(
                          child: DetailActionHeader(
                            backLabel: 'Back to playlists',
                            onBack: () => Navigator.of(context).pop(),
                            actions: _selectionMode
                                ? DownloadSelectionToolbar(
                                    selectedCount: selectedTracks.length,
                                    totalCount: removableTracks.length,
                                    onCancel: _clearSelection,
                                    onSelectAll: () =>
                                        _selectAll(removableTracks),
                                    onDeselectAll: _deselectAll,
                                    onRemove: selectedTracks.isEmpty
                                        ? null
                                        : () => _removeDownloads(
                                            controller,
                                            selectedTracks,
                                            playlist.name,
                                          ),
                                  )
                                : Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Tooltip(
                                        message: 'Play playlist',
                                        child: ObsidianHudIconButton(
                                          icon: Icons.play_arrow_rounded,
                                          onPressed:
                                              _tracksLoading ||
                                                  displayedTracks.isEmpty
                                              ? null
                                              : () => widget.isLocal
                                                    ? controller
                                                          .playLocalPlaylistFromTop(
                                                            widget.playlistId,
                                                          )
                                                    : controller
                                                          .playPlaylistFromTop(
                                                            widget.playlistId,
                                                          ),
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Edit details',
                                        child: ObsidianHudIconButton(
                                          icon: Icons.edit_note_rounded,
                                          onPressed: () =>
                                              _openRename(controller, playlist),
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Edit tracks',
                                        child: ObsidianHudIconButton(
                                          icon: Icons.playlist_remove_rounded,
                                          onPressed: removableTracks.isEmpty
                                              ? null
                                              : _startSelection,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        sliver: SliverToBoxAdapter(
                          child: AlbumHero(
                            album: playlistAlbum,
                            coverUrl: playlistCoverUrl,
                            headers: playlistHeaders,
                          ),
                        ),
                      ),
                      if (_tracksLoading)
                        loadingSliver()
                      else if (displayedTracks.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: _EmptyPlaylistText()),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          sliver: StreamBuilder<PlaybackState>(
                            stream: controller.playbackStream,
                            initialData: controller.playbackState,
                            builder: (context, playbackSnapshot) {
                              final playback =
                                  playbackSnapshot.data ??
                                  controller.playbackState;
                              final playingId = playback.track?.id;
                              return TrackSliverList(
                                tracks: displayedTracks,
                                showAlbumArt: true,
                                isPlayingTrack: (track) =>
                                    playback.isPlaying && playingId == track.id,
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
                                      scope: widget.isLocal
                                          ? ActionScope.local
                                          : ActionScope.server,
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
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _loadTracksIfNeeded(AppController controller, {bool force = false}) {
    final key = _tracksLoadKey;
    if (!force && _activeTracksLoadKey == key) {
      return;
    }
    _activeTracksLoadKey = key;
    final requestId = ++_tracksLoadRequestId;

    if (!_tracksLoading || _selectionMode || _selectedTrackIds.isNotEmpty) {
      setState(() {
        _tracksLoading = true;
        _selectionMode = false;
        _selectedTrackIds.clear();
      });
    } else {
      _selectedTrackIds.clear();
    }

    final loadFuture = widget.isLocal
        ? controller.loadLocalPlaylistTracks(widget.playlistId)
        : controller.loadPlaylistTracks(widget.playlistId);
    unawaited(
      loadFuture
          .whenComplete(() {
            if (!mounted ||
                requestId != _tracksLoadRequestId ||
                _tracksLoadKey != key) {
              return;
            }
            setState(() => _tracksLoading = false);
          })
          .catchError((Object _) {}),
    );
  }

  String get _tracksLoadKey {
    return '${widget.isLocal ? 'local' : 'server'}:${widget.playlistId}';
  }

  void _openRename(AppController controller, Playlist playlist) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Rename playlist',
        initialValue: playlist.name,
        initialDescription: playlist.description ?? '',
        initialImageUrl: widget.isLocal
            ? playlist.imagePath
            : _serverPlaylistCoverUrl(controller, playlist),
        imageHeaders: widget.isLocal
            ? const <String, String>{}
            : authHeaders(controller),
        onSubmit: (value, description, imageEdit, _) => widget.isLocal
            ? controller.renameLocalPlaylist(
                playlist.id,
                value,
                description: description,
                imageEdit: imageEdit,
              )
            : controller.renamePlaylist(
                playlist.id,
                value,
                description: description,
                imageEdit: imageEdit,
              ),
      ),
    );
  }

  String? _serverPlaylistCoverUrl(AppController controller, Playlist playlist) {
    final imageRef = playlist.imageRef?.trim();
    if (imageRef == null || imageRef.isEmpty) {
      return null;
    }
    return controller.connection.buildPlaylistCoverUrl(
      playlist.id,
      imageRef: imageRef,
    );
  }

  Album _playlistAlbum(Playlist playlist) {
    return Album(
      id: playlist.id,
      title: playlist.name,
      artist: 'Playlist',
      artistId: '',
      trackCount: playlist.trackIds.length,
      summary: playlist.description,
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
