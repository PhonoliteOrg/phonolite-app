import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../entities/models.dart';
import '../widgets/display/playlist_module_card.dart';
import '../widgets/layouts/app_scope.dart';
import '../widgets/modals/playlist_editor_modal.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/tech_button.dart';
import 'playlist_detail_view.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (controller.playlists.isEmpty) {
      controller.loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return StreamBuilder<List<Playlist>>(
      stream: controller.playlistsStream,
      initialData: controller.playlists,
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _HeaderRow(
                  count: playlists.length,
                  onCreate: () => _openCreate(controller),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: playlists.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: _EmptyPlaylistsText()),
                    )
                  : SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 520,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 80,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final playlist = playlists[index];
                          return PlaylistModuleCard(
                            playlist: playlist,
                            onTap: () => _openDetail(context, playlist),
                            onLongPress: () =>
                                controller.queuePlaylist(playlist.id),
                          );
                        },
                        childCount: playlists.length,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _openDetail(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistDetailView(playlistId: playlist.id),
      ),
    );
  }

  void _openCreate(AppController controller) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Create playlist',
        initialValue: '',
        onSubmit: controller.createPlaylist,
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.count, required this.onCreate});

  final int count;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Icon(Icons.queue_music, size: 42),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playlists',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      letterSpacing: 1.1,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '$count LISTS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: ObsidianPalette.textMuted,
                      letterSpacing: 1.4,
                    ),
              ),
            ],
          ),
        ),
        TechButton(
          label: 'Create New',
          icon: Icons.add,
          onTap: onCreate,
        ),
      ],
    );
  }
}

class _EmptyPlaylistsText extends StatelessWidget {
  const _EmptyPlaylistsText();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No Playlists',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
