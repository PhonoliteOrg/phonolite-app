import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/playlists_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/pages/playlists/playlist_detail_view.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_editor_modal.dart';
import 'package:phonolite_app/ui/features/playlists/widgets/playlist_section.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_widgets.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/music/artwork/artwork_helpers.dart';
import 'package:phonolite_app/ui/shared/music/collection_view_toggle_button.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class PlaylistsPage extends BasePage {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends BasePageState<PlaylistsPage> {
  late final PlaylistsController _feature = bindController(PlaylistsController(AppScope.of(context)));

  void _openDetail(BuildContext context, Playlist playlist, {required bool isLocal}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlaylistDetailView(playlistId: playlist.id, isLocal: isLocal),
      ),
    );
  }

  Future<void> _createPlaylist(
    AppController controller, {
    required String name,
    required String description,
    required PlaylistImageEdit imageEdit,
    required PlaylistEditorTarget target,
    required bool canCreateServer,
  }) {
    if (target == PlaylistEditorTarget.server && canCreateServer) {
      return controller.createPlaylist(name, description: description, imageEdit: imageEdit);
    }

    return controller.createLocalPlaylist(name, description: description, imageEdit: imageEdit);
  }

  void _openCreate(AppController controller, {required bool canCreateServer}) {
    showDialog<void>(
      context: context,
      builder: (context) => PlaylistEditorModal(
        title: 'Create playlist',
        initialValue: '',
        showTargetSelector: canCreateServer,
        onSubmit: (name, description, imageEdit, target) => _createPlaylist(
          controller,
          name: name,
          description: description,
          imageEdit: imageEdit,
          target: target,
          canCreateServer: canCreateServer,
        ),
      ),
    );
  }

  Future<void> _deleteSelectedPlaylists(
    AppController controller, {
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) async {
    final selected = _feature.selectedPlaylists(localPlaylists: localPlaylists, serverPlaylists: serverPlaylists);

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

    await _feature.deletePlaylists(selected);
  }

  Widget _playlistSection(
    BuildContext context,
    AppController controller, {
    required List<Playlist> playlists,
    required bool showListView,
    required bool isLocal,
    required String? title,
    required String emptyText,
    required Map<String, String> headers,
  }) => PlaylistSection(
    title: title,
    playlists: playlists,
    showListView: showListView,
    headers: headers,
    coverUrlFor: isLocal
        ? (playlist) => playlist.imagePath
        : (playlist) => _feature.serverPlaylistCoverUrl(controller, playlist),
    onOpen: (playlist) => _openDetail(context, playlist, isLocal: isLocal),
    onPlayFromTop: isLocal
        ? (playlist) => controller.playLocalPlaylistFromTop(playlist.id)
        : (playlist) => controller.playPlaylistFromTop(playlist.id),
    selectionMode: _feature.selectionMode,
    isSelected: (playlist) => _feature.selectedPlaylistKeys.contains(_feature.selectionKey(playlist, isLocal: isLocal)),
    isDeleting: (playlist) => _feature.deletingPlaylistKeys.contains(_feature.selectionKey(playlist, isLocal: isLocal)),
    onSelectionToggle: (playlist) => _feature.toggleSelection(playlist, isLocal: isLocal),
    emptyText: emptyText,
  );

  Widget _playlistsContent(
    BuildContext context,
    PageAssembler assemble,
    AppController controller, {
    required AsyncSnapshot<bool> viewModeSnapshot,
    required AuthState authState,
    required List<Playlist> localPlaylists,
    required List<Playlist> serverPlaylists,
  }) {
    final showListView = viewModeSnapshot.data ?? controller.collectionListMode;
    final authHeadersMap = authHeaders(controller);
    final totalPlaylistCount = localPlaylists.length + serverPlaylists.length;
    final selectedPlaylists = _feature.selectedPlaylists(
      localPlaylists: localPlaylists,
      serverPlaylists: serverPlaylists,
    );

    final useCompactHeaderActions = PageToolbarActionLayout.of(context).compact;
    final headerActionIconSize = PageToolbarActionLayout.of(context).iconSize;
    final headerActionSpacing = PageToolbarActionLayout.of(context).spacing;

    return assemble(
      context,
      navbar: LibraryHeader(
        title: 'PLAYLISTS',
        trailing: _feature.selectionMode
            ? DownloadSelectionToolbar(
                selectedCount: selectedPlaylists.length,
                totalCount: totalPlaylistCount,
                onCancel: _feature.clearSelection,
                onSelectAll: () => _feature.selectAll(localPlaylists: localPlaylists, serverPlaylists: serverPlaylists),
                onDeselectAll: _feature.deselectAll,
                onRemove: selectedPlaylists.isEmpty
                    ? null
                    : () => _deleteSelectedPlaylists(
                        controller,
                        localPlaylists: localPlaylists,
                        serverPlaylists: serverPlaylists,
                      ),
              )
            : PageToolbarActions(
                spacing: headerActionSpacing,
                runSpacing: useCompactHeaderActions ? 4 : 8,
                children: [
                  Tooltip(
                    message: 'Create playlist',
                    child: ObsidianHudIconButton(
                      icon: PhonoliteIcons.plus,
                      size: headerActionIconSize,
                      onPressed: () => _openCreate(controller, canCreateServer: authState.isAuthorized),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit playlists',
                    child: ObsidianHudIconButton(
                      iconWidget: const EditIcon(),
                      size: headerActionIconSize,
                      onPressed: totalPlaylistCount == 0 ? null : _feature.startSelection,
                    ),
                  ),
                  CollectionViewToggleButton(
                    isListView: showListView,
                    semanticLabel: 'Playlist collection view',
                    iconSize: headerActionIconSize,
                    onPressed: controller.toggleCollectionListMode,
                  ),
                ],
              ),
      ),
      body: PageBody.slivers(
        slivers: [
          _playlistSection(
            context,
            controller,
            playlists: localPlaylists,
            showListView: showListView,
            isLocal: true,
            title: authState.isAuthorized ? 'Local Playlists' : null,
            emptyText: authState.isAuthorized ? 'No local playlists' : 'No playlists',
            headers: const <String, String>{},
          ),
          if (authState.isAuthorized)
            _playlistSection(
              context,
              controller,
              playlists: serverPlaylists,
              showListView: showListView,
              isLocal: false,
              title: 'Server Playlists',
              emptyText: 'No server playlists',
              headers: authHeadersMap,
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
                  builder: (context, viewModeSnapshot) => _playlistsContent(
                    context,
                    assemble,
                    controller,
                    viewModeSnapshot: viewModeSnapshot,
                    authState: authState,
                    localPlaylists: localPlaylists,
                    serverPlaylists: serverPlaylists,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
