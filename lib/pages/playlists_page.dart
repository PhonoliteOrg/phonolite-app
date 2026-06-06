import 'package:flutter/material.dart';

import '../core/library_helpers.dart';
import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../widgets/display/album_card.dart';
import '../widgets/display/album_row_tile.dart';
import '../widgets/display/download_selection_toolbar.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layout/safe_sliver_grid.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/confirmation_modal.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/ui/collection_view_toggle_button.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';
import '../widgets/ui/tech_button.dart';
import 'playlist_detail_view.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  bool _requestedLocalLoad = false;
  bool _requestedServerLoad = false;
  bool _selectionMode = false;
  final Set<String> _selectedPlaylistKeys = <String>{};
  final Set<String> _deletingPlaylistKeys = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (!_requestedLocalLoad) {
      _requestedLocalLoad = true;
      controller.loadLocalPlaylists();
    }
    if (controller.authState.isAuthorized &&
        !_requestedServerLoad &&
        controller.playlists.isEmpty) {
      _requestedServerLoad = true;
      controller.loadPlaylists();
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
            controller.playlists.isEmpty) {
          _requestedServerLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.authState.isAuthorized) {
              controller.loadPlaylists();
            }
          });
        }
        return StreamBuilder<List<Playlist>>(
          stream: controller.localPlaylistsStream,
          initialData: controller.localPlaylists,
          builder: (context, localSnapshot) {
            final localPlaylists = localSnapshot.data ?? const <Playlist>[];
            return StreamBuilder<List<Playlist>>(
              stream: controller.playlistsStream,
              initialData: controller.playlists,
              builder: (context, serverSnapshot) {
                final serverPlaylists = authState.isAuthorized
                    ? serverSnapshot.data ?? const <Playlist>[]
                    : const <Playlist>[];
                return StreamBuilder<bool>(
                  stream: controller.collectionListModeStream,
                  initialData: controller.collectionListMode,
                  builder: (context, viewModeSnapshot) {
                    final showListView =
                        viewModeSnapshot.data ?? controller.collectionListMode;
                    final authHeadersMap = authHeaders(controller);
                    final totalPlaylistCount =
                        localPlaylists.length + serverPlaylists.length;
                    final selectedPlaylists = _selectedPlaylists(
                      localPlaylists: localPlaylists,
                      serverPlaylists: serverPlaylists,
                    );
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          sliver: SliverToBoxAdapter(
                            child: LibraryHeader(
                              title: 'PLAYLISTS',
                              moduleCount: 0,
                              trailing: _selectionMode
                                  ? DownloadSelectionToolbar(
                                      selectedCount: selectedPlaylists.length,
                                      totalCount: totalPlaylistCount,
                                      onCancel: _clearSelection,
                                      onSelectAll: () => _selectAll(
                                        localPlaylists: localPlaylists,
                                        serverPlaylists: serverPlaylists,
                                      ),
                                      onDeselectAll: _deselectAll,
                                      onRemove: selectedPlaylists.isEmpty
                                          ? null
                                          : () => _deleteSelectedPlaylists(
                                              controller,
                                              localPlaylists: localPlaylists,
                                              serverPlaylists: serverPlaylists,
                                            ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Tooltip(
                                          message: 'Create playlist',
                                          child: ObsidianHudIconButton(
                                            icon: Icons.add_rounded,
                                            onPressed: () => _openCreate(
                                              controller,
                                              canCreateServer:
                                                  authState.isAuthorized,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Tooltip(
                                          message: 'Edit playlists',
                                          child: ObsidianHudIconButton(
                                            icon: Icons.edit_rounded,
                                            onPressed: totalPlaylistCount == 0
                                                ? null
                                                : _startSelection,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        CollectionViewToggleButton(
                                          isListView: showListView,
                                          semanticLabel:
                                              'Playlist collection view',
                                          onPressed: controller
                                              .toggleCollectionListMode,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        _PlaylistSection(
                          title: authState.isAuthorized
                              ? 'Local Playlists'
                              : null,
                          playlists: localPlaylists,
                          showListView: showListView,
                          headers: const <String, String>{},
                          coverUrlFor: (playlist) => playlist.imagePath,
                          onOpen: (playlist) =>
                              _openDetail(context, playlist, isLocal: true),
                          onPlayFromTop: (playlist) =>
                              controller.playLocalPlaylistFromTop(playlist.id),
                          selectionMode: _selectionMode,
                          isSelected: (playlist) => _selectedPlaylistKeys
                              .contains(_selectionKey(playlist, isLocal: true)),
                          isDeleting: (playlist) => _deletingPlaylistKeys
                              .contains(_selectionKey(playlist, isLocal: true)),
                          onSelectionToggle: (playlist) =>
                              _toggleSelection(playlist, isLocal: true),
                          emptyText: authState.isAuthorized
                              ? 'No local playlists'
                              : 'No playlists',
                        ),
                        if (authState.isAuthorized)
                          _PlaylistSection(
                            title: 'Server Playlists',
                            playlists: serverPlaylists,
                            showListView: showListView,
                            headers: authHeadersMap,
                            coverUrlFor: (playlist) =>
                                _serverPlaylistCoverUrl(controller, playlist),
                            onOpen: (playlist) =>
                                _openDetail(context, playlist, isLocal: false),
                            onPlayFromTop: (playlist) =>
                                controller.playPlaylistFromTop(playlist.id),
                            selectionMode: _selectionMode,
                            isSelected: (playlist) =>
                                _selectedPlaylistKeys.contains(
                                  _selectionKey(playlist, isLocal: false),
                                ),
                            isDeleting: (playlist) =>
                                _deletingPlaylistKeys.contains(
                                  _selectionKey(playlist, isLocal: false),
                                ),
                            onSelectionToggle: (playlist) =>
                                _toggleSelection(playlist, isLocal: false),
                            emptyText: 'No server playlists',
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

  void _openDetail(
    BuildContext context,
    Playlist playlist, {
    required bool isLocal,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PlaylistDetailView(playlistId: playlist.id, isLocal: isLocal),
      ),
    );
  }

  void _openCreate(AppController controller, {required bool canCreateServer}) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Create playlist',
        initialValue: '',
        showTargetSelector: canCreateServer,
        onSubmit: (name, description, imageEdit, target) {
          if (target == PlaylistEditorTarget.server && canCreateServer) {
            return controller.createPlaylist(
              name,
              description: description,
              imageEdit: imageEdit,
            );
          }
          return controller.createLocalPlaylist(
            name,
            description: description,
            imageEdit: imageEdit,
          );
        },
      ),
    );
  }

  List<_SelectedPlaylist> _selectedPlaylists({
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) {
    final selected = <_SelectedPlaylist>[];
    for (final playlist in localPlaylists) {
      final key = _selectionKey(playlist, isLocal: true);
      if (_selectedPlaylistKeys.contains(key)) {
        selected.add(_SelectedPlaylist(playlist: playlist, isLocal: true));
      }
    }
    for (final playlist in serverPlaylists) {
      final key = _selectionKey(playlist, isLocal: false);
      if (_selectedPlaylistKeys.contains(key)) {
        selected.add(_SelectedPlaylist(playlist: playlist, isLocal: false));
      }
    }
    return selected;
  }

  void _startSelection() {
    setState(() {
      _selectionMode = true;
      _selectedPlaylistKeys.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPlaylistKeys.clear();
    });
  }

  void _deselectAll() {
    setState(() => _selectedPlaylistKeys.clear());
  }

  void _selectAll({
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) {
    setState(() {
      _selectedPlaylistKeys
        ..clear()
        ..addAll(
          localPlaylists.map(
            (playlist) => _selectionKey(playlist, isLocal: true),
          ),
        )
        ..addAll(
          serverPlaylists.map(
            (playlist) => _selectionKey(playlist, isLocal: false),
          ),
        );
    });
  }

  void _toggleSelection(Playlist playlist, {required bool isLocal}) {
    final key = _selectionKey(playlist, isLocal: isLocal);
    setState(() {
      if (!_selectedPlaylistKeys.remove(key)) {
        _selectedPlaylistKeys.add(key);
      }
    });
  }

  Future<void> _deleteSelectedPlaylists(
    AppController controller, {
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) async {
    final selected = _selectedPlaylists(
      localPlaylists: localPlaylists,
      serverPlaylists: serverPlaylists,
    );
    if (selected.isEmpty) {
      return;
    }
    final confirmed = await ConfirmationModal.show(
      context,
      title: selected.length == 1 ? 'Delete playlist' : 'Delete playlists',
      message: selected.length == 1
          ? 'Are you sure you want to delete this playlist?'
          : 'Are you sure you want to delete these playlists?',
      actionChrome: TechButtonChrome.borderless,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final keys = selected
        .map((item) => _selectionKey(item.playlist, isLocal: item.isLocal))
        .toSet();
    setState(() => _deletingPlaylistKeys.addAll(keys));
    try {
      for (final item in selected) {
        if (item.isLocal) {
          await controller.deleteLocalPlaylist(item.playlist.id);
        } else {
          await controller.deletePlaylist(item.playlist.id);
        }
      }
      if (mounted) {
        setState(() {
          _selectedPlaylistKeys.removeAll(keys);
          _deletingPlaylistKeys.removeAll(keys);
          _selectionMode = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _deletingPlaylistKeys.removeAll(keys));
      }
    }
  }

  String _selectionKey(Playlist playlist, {required bool isLocal}) {
    return '${isLocal ? 'local' : 'server'}:${playlist.id}';
  }
}

class _SelectedPlaylist {
  const _SelectedPlaylist({required this.playlist, required this.isLocal});

  final Playlist playlist;
  final bool isLocal;
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({
    required this.title,
    required this.playlists,
    required this.showListView,
    required this.headers,
    required this.coverUrlFor,
    required this.onOpen,
    required this.onPlayFromTop,
    required this.selectionMode,
    required this.isSelected,
    required this.isDeleting,
    required this.onSelectionToggle,
    required this.emptyText,
  });

  final String? title;
  final List<Playlist> playlists;
  final bool showListView;
  final Map<String, String> headers;
  final String? Function(Playlist playlist) coverUrlFor;
  final ValueChanged<Playlist> onOpen;
  final ValueChanged<Playlist> onPlayFromTop;
  final bool selectionMode;
  final bool Function(Playlist playlist) isSelected;
  final bool Function(Playlist playlist) isDeleting;
  final ValueChanged<Playlist> onSelectionToggle;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (title != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(child: _HeaderRow(title: title!)),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, title == null ? 8 : 8, 20, 24),
          sliver: playlists.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      emptyText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ObsidianPalette.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                )
              : showListView
              ? SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index.isOdd) {
                      return const Divider(height: 1);
                    }
                    final playlist = playlists[index ~/ 2];
                    return AlbumRowTile(
                      album: _playlistAlbum(playlist),
                      coverUrl: coverUrlFor(playlist) ?? '',
                      headers: headers,
                      onTap: () => onOpen(playlist),
                      onLongPress: playlist.trackIds.isEmpty
                          ? null
                          : () => onPlayFromTop(playlist),
                      trailing: selectionMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Play playlist',
                                  child: ObsidianHudIconButton(
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: playlist.trackIds.isEmpty
                                        ? null
                                        : () => onPlayFromTop(playlist),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white38,
                                ),
                              ],
                            ),
                      selectionMode: selectionMode,
                      selected: isSelected(playlist),
                      isDeleting: isDeleting(playlist),
                      onSelectionToggle: () => onSelectionToggle(playlist),
                    );
                  }, childCount: playlists.length * 2 - 1),
                )
              : SafeSliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final playlist = playlists[index];
                    return AlbumCard(
                      album: _playlistAlbum(playlist),
                      coverUrl: coverUrlFor(playlist) ?? '',
                      headers: headers,
                      onTap: () => onOpen(playlist),
                      onPlay: playlist.trackIds.isEmpty
                          ? null
                          : () => onPlayFromTop(playlist),
                      onLongPress: playlist.trackIds.isEmpty
                          ? null
                          : () => onPlayFromTop(playlist),
                      selectionMode: selectionMode,
                      selected: isSelected(playlist),
                      isDeleting: isDeleting(playlist),
                      onSelectionToggle: () => onSelectionToggle(playlist),
                    );
                  }, childCount: playlists.length),
                ),
        ),
      ],
    );
  }

  Album _playlistAlbum(Playlist playlist) {
    return Album(
      id: playlist.id,
      title: playlist.name,
      artist: 'Playlist',
      artistId: '',
      trackCount: playlist.trackIds.length,
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ObsidianSectionHeader(title: title);
  }
}
