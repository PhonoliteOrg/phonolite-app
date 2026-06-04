import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/auth_state.dart';
import '../entities/models.dart';
import '../widgets/display/playlist_module_card.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/layout/safe_sliver_grid.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';
import 'playlist_detail_view.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  bool _requestedLocalLoad = false;
  bool _requestedServerLoad = false;

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
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: LibraryHeader(
                          title: 'PLAYLISTS',
                          moduleCount:
                              localPlaylists.length + serverPlaylists.length,
                        ),
                      ),
                    ),
                    _PlaylistSection(
                      title: 'Local Playlists',
                      subtitle: '${localPlaylists.length} lists',
                      playlists: localPlaylists,
                      onCreate: () => _openCreateLocal(controller),
                      onOpen: (playlist) =>
                          _openDetail(context, playlist, isLocal: true),
                      onQueue: (playlist) =>
                          controller.queueLocalPlaylist(playlist.id),
                      emptyText: 'No local playlists',
                    ),
                    if (authState.isAuthorized)
                      _PlaylistSection(
                        title: 'Server Playlists',
                        subtitle: '${serverPlaylists.length} lists',
                        playlists: serverPlaylists,
                        onCreate: () => _openCreateServer(controller),
                        onOpen: (playlist) =>
                            _openDetail(context, playlist, isLocal: false),
                        onQueue: (playlist) =>
                            controller.queuePlaylist(playlist.id),
                        emptyText: 'No server playlists',
                      )
                    else
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Connect to a server to show server playlists.',
                            style: TextStyle(color: ObsidianPalette.textMuted),
                          ),
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

  void _openCreateLocal(AppController controller) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Create local playlist',
        initialValue: '',
        onSubmit: controller.createLocalPlaylist,
      ),
    );
  }

  void _openCreateServer(AppController controller) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Create server playlist',
        initialValue: '',
        onSubmit: controller.createPlaylist,
      ),
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({
    required this.title,
    required this.subtitle,
    required this.playlists,
    required this.onCreate,
    required this.onOpen,
    required this.onQueue,
    required this.emptyText,
  });

  final String title;
  final String subtitle;
  final List<Playlist> playlists;
  final VoidCallback onCreate;
  final ValueChanged<Playlist> onOpen;
  final ValueChanged<Playlist> onQueue;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(
            child: _HeaderRow(
              title: title,
              subtitle: subtitle,
              onCreate: onCreate,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
              : SafeSliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: 80,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final playlist = playlists[index];
                    return PlaylistModuleCard(
                      playlist: playlist,
                      onTap: () => onOpen(playlist),
                      onLongPress: () => onQueue(playlist),
                    );
                  }, childCount: playlists.length),
                ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    required this.subtitle,
    required this.onCreate,
  });

  final String title;
  final String subtitle;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ObsidianSectionHeader(
      title: title,
      subtitle: subtitle,
      trailing: Tooltip(
        message: 'Create New',
        child: ObsidianHudIconButton(
          icon: Icons.add_rounded,
          onPressed: onCreate,
        ),
      ),
    );
  }
}
