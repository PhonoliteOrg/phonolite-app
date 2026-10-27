import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playlists/add_to_playlist_controller.dart';
import 'package:phonolite_app/data/models/collections/playlist.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/search_hud.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/local_server_toggle.dart';
import 'package:phonolite_app/ui/structures/modals/base_alert_modal.dart';

Future<void> showAddToPlaylistModalForTrack(BuildContext context, Track? track, {required ActionScope scope}) async {
  if (track == null) {
    return;
  }

  final controller = AppScope.of(context);
  final source = controller.localPlaylistSourceForTrack(track);
  final sourceTrack = source == null
      ? track
      : track.copyWith(serverBaseUrl: source.serverBaseUrl, serverTrackId: source.serverTrackId);
  final actions = await AddToPlaylistController.prepareActions(controller, sourceTrack, scope);

  if (!context.mounted || actions == null) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AddToPlaylistModal(
      scope: scope,
      playlists: actions.playlists,
      playlistChanges: actions.playlistChanges,
      trackId: actions.trackId,
      canUsePlaylists: actions.canUsePlaylists,
      onSelected: actions.add,
      onRemoved: actions.remove,
      containsTrack: actions.containsTrack,
      actionsForScope: (selectedScope) =>
          AddToPlaylistController.prepareActions(controller, sourceTrack, selectedScope),
    ),
  );
}

class AddToPlaylistModal extends BaseAlertModal {
  final ActionScope scope;
  final List<Playlist> playlists;
  final Stream<List<Playlist>>? playlistChanges;
  final String trackId;
  final bool canUsePlaylists;
  final PlaylistTrackMutation onSelected;
  final PlaylistTrackMutation? onRemoved;
  final bool Function(Playlist playlist)? containsTrack;
  final Future<PlaylistTrackActions?> Function(ActionScope scope)? actionsForScope;

  const AddToPlaylistModal({
    super.key,
    required this.scope,
    required this.playlists,
    required this.trackId,
    required this.canUsePlaylists,
    required this.onSelected,
    this.onRemoved,
    this.playlistChanges,
    this.containsTrack,
    this.actionsForScope,
  });

  @override
  State<AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends BaseAlertModalState<AddToPlaylistModal> {
  late ActionScope _scope = widget.scope;
  late PlaylistTrackActions _actions = _widgetActions();
  int _scopeRequest = 0;
  late final AddToPlaylistController _feature = bindController(
    AddToPlaylistController(playlists: widget.playlists, playlistChanges: widget.playlistChanges),
  );
  late final TextEditingController _controller;
  late final ScrollController _listController;

  @override
  bool get modalScrollable => true;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController();
    _listController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant AddToPlaylistModal oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.playlists, widget.playlists) ||
        oldWidget.playlistChanges != widget.playlistChanges ||
        oldWidget.trackId != widget.trackId ||
        oldWidget.scope != widget.scope) {
      _scopeRequest++;
      _scope = widget.scope;
      _actions = _widgetActions();
      _feature.setPlaylistSource(playlists: widget.playlists, playlistChanges: widget.playlistChanges);
    }
  }

  @override
  void dispose() {
    _scopeRequest++;
    _listController.dispose();
    _controller.dispose();

    super.dispose();
  }

  Future<void> _selectScope(ActionScope scope) async {
    final loadActions = widget.actionsForScope;

    if (scope == _scope || loadActions == null) {
      return;
    }

    final request = ++_scopeRequest;
    setState(() {
      _scope = scope;
      _actions = PlaylistTrackActions(
        playlists: const [],
        trackId: widget.trackId,
        canUsePlaylists: false,
        add: (_) {},
        remove: (_) {},
      );
    });
    _feature.setPlaylistSource(playlists: const [], resetActions: true);

    try {
      final actions = await loadActions(scope);

      if (!mounted || request != _scopeRequest || actions == null) {
        return;
      }

      setState(() => _actions = actions);
      _feature.setPlaylistSource(playlists: actions.playlists, playlistChanges: actions.playlistChanges);
    } catch (error, stackTrace) {
      _feature.reportInitializationFailure(error, stackTrace);
    }
  }

  PlaylistTrackActions _widgetActions() => PlaylistTrackActions(
    playlists: widget.playlists,
    playlistChanges: widget.playlistChanges,
    trackId: widget.trackId,
    canUsePlaylists: widget.canUsePlaylists,
    add: widget.onSelected,
    remove: widget.onRemoved ?? (_) {},
    containsTrack: widget.containsTrack,
  );

  void _updateQuery() {
    _feature.setQuery(_controller.text);
  }

  Future<void> _confirmRemoval(BuildContext context, Playlist playlist) async {
    final request = _scopeRequest;
    final remove = _actions.remove;
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Remove song from playlist',
      message: 'Are you sure you want to remove this song from this playlist?',
    );

    if (!confirmed || !mounted || request != _scopeRequest) {
      return;
    }

    await _feature.remove(playlist, remove);
  }

  Widget _buildPlaylistRow(BuildContext context, Playlist playlist) {
    final isInPlaylist = _feature.contains(playlist, _actions.trackId, containsTrack: _actions.containsTrack);
    final count = _feature.trackCount(playlist, _actions.trackId, containsTrack: _actions.containsTrack);
    final disabled = !_actions.canUsePlaylists;
    final mutating = _feature.isMutating(playlist);
    final scopeLabel = _scope == ActionScope.local ? 'Local' : 'Server';
    final onAdd = isInPlaylist || disabled || mutating ? null : () => _feature.add(playlist, _actions.add);

    final String subtitle;

    if (disabled) {
      subtitle = _scope == ActionScope.local ? 'Unavailable locally' : 'Unavailable on this server';
    } else {
      subtitle = '$scopeLabel - $count tracks';
    }

    return ObsidianModalListRow(
      title: playlist.name,
      subtitle: subtitle,
      trailing: Tooltip(
        message: isInPlaylist ? 'Remove from playlist' : 'Add to playlist',
        child: ObsidianHudIconButton(
          icon: isInPlaylist ? PhonoliteIcons.trash2 : PhonoliteIcons.plus,
          size: ObsidianModalScope.usesTouchTargets(context) ? 24 : 20,
          onPressed: isInPlaylist && !mutating && (widget.onRemoved != null || widget.actionsForScope != null)
              ? () => _confirmRemoval(context, playlist)
              : onAdd,
        ),
      ),
      enabled: !isInPlaylist && !disabled,
      isSelected: isInPlaylist,
      onTap: onAdd,
    );
  }

  @override
  Widget modalTitle(BuildContext context) =>
      Text('Add to ${_scope == ActionScope.local ? 'local' : 'server'} playlist');

  @override
  Widget modalContent(BuildContext context) {
    final hasPlaylists = _feature.playlists.isNotEmpty;
    final filteredPlaylists = _feature.filter(_feature.playlists);
    final scopeLabel = _scope == ActionScope.local ? 'local' : 'server';

    return SizedBox(
      width: 360,
      height: 420,
      child: Column(
        children: [
          if (widget.actionsForScope != null) ...[
            LocalServerToggle(value: _scope, onChanged: (scope) => unawaited(_selectScope(scope))),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: hasPlaylists
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SearchHud(
                        controller: _controller,
                        height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
                        hintText: 'Search playlists',
                        onChanged: _updateQuery,
                        onSubmit: _updateQuery,
                        onClear: _updateQuery,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Scrollbar(
                          controller: _listController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _listController,
                            shrinkWrap: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                            itemCount: filteredPlaylists.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: ObsidianPalette.textMuted.withValues(alpha: 0.25)),
                            itemBuilder: (context, index) {
                              return _buildPlaylistRow(context, filteredPlaylists[index]);
                            },
                          ),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No $scopeLabel playlists available.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  List<Widget> modalActions(BuildContext context) => [
    ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
  ];
}
