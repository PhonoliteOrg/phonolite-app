import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/playback/shuffle_presets_controller.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_options.dart';
import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/downloads/widgets/download_selection_toolbar.dart';
import 'package:phonolite_app/ui/features/playback/widgets/shuffle_preset_editor_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/edit_icon.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/confirmation_modal.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/local_server_toggle.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';
import 'package:phonolite_app/ui/shell/toolbars/detail_action_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';
import 'package:phonolite_app/ui/shell/toolbars/page_toolbar_actions.dart';

class CustomShuffleSettingsPage extends BasePage {
  static const String routeName = '/settings/custom-shuffle';

  const CustomShuffleSettingsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    settings: const RouteSettings(name: routeName),
    builder: (_) => const CustomShuffleSettingsPage(),
  );

  @override
  State<CustomShuffleSettingsPage> createState() => _CustomShuffleSettingsPageState();
}

class _CustomShuffleSettingsPageState extends BasePageState<CustomShuffleSettingsPage> {
  late final ShufflePresetsController _feature = bindController(ShufflePresetsController(AppScope.of(context)));

  @override
  bool get usesScaffold => true;

  @override
  bool get usesSafeArea => true;

  @override
  EdgeInsetsGeometry get navbarPadding => const EdgeInsets.only(bottom: 8);

  Future<void> _openEditor({ShufflePreset? preset, bool local = false}) => showDialog<void>(
    context: context,
    builder: (_) => ShufflePresetEditorModal(app: _feature.app, preset: preset, local: local),
  );

  Future<void> _deleteSelected() async {
    final selected = _feature.selectedPresets;
    final revision = _feature.app.connection.sessionRevision;
    final confirmed = await ConfirmationModal.show(
      context,
      title: 'Delete custom shuffles',
      message:
          'Delete ${selected.length} selected custom ${selected.length == 1 ? 'shuffle' : 'shuffles'} from your account?',
      confirmLabel: 'Delete',
    );

    if (mounted && confirmed && _feature.app.connection.sessionRevision == revision) {
      await _feature.deleteSelected(selected);
    }
  }

  Widget _headerActions(BuildContext context, List<ShufflePreset> presets) {
    final local = _feature.target == CustomShuffleTarget.local;
    final available = _feature.app.shufflePresetsAvailable && !_feature.busy;
    final layout = PageToolbarActionLayout.of(context);

    if (_feature.selectionMode && !local) {
      return DownloadSelectionToolbar(
        selectedCount: _feature.selectedIds.length,
        totalCount: presets.length,
        onCancel: _feature.clearSelection,
        onSelectAll: _feature.selectAll,
        onDeselectAll: _feature.deselectAll,
        onRemove: available ? () => unawaited(_deleteSelected()) : null,
      );
    }

    return PageToolbarActions(
      spacing: layout.spacing,
      runSpacing: layout.runSpacing,
      children: [
        if (!local)
          Tooltip(
            message: 'Create custom shuffle',
            child: ObsidianHudIconButton(
              icon: PhonoliteIcons.plus,
              size: layout.iconSize,
              onPressed: available ? () => unawaited(_openEditor()) : null,
            ),
          ),
        Tooltip(
          message: local ? 'Edit local filters' : 'Edit custom shuffles',
          child: ObsidianHudIconButton(
            iconWidget: const EditIcon(),
            size: layout.iconSize,
            onPressed: local
                ? () => unawaited(_openEditor(local: true))
                : (available && presets.isNotEmpty ? _feature.startSelection : null),
          ),
        ),
      ],
    );
  }

  Widget _presetRow(ShufflePreset preset) {
    final selected = _feature.selectedIds.contains(preset.id);

    return ObsidianListRow(
      leading: _feature.selectionMode
          ? LucideCheckbox(value: selected, onChanged: (_) => _feature.toggleSelection(preset.id))
          : const Icon(PhonoliteIcons.shuffle, color: ObsidianPalette.textMuted),
      title: preset.name,
      subtitle: '${preset.artistIds.length} artists · ${preset.genres.length} genres',
      isActive: selected,
      enabled: !_feature.busy,
      onTap: _feature.selectionMode
          ? () => _feature.toggleSelection(preset.id)
          : () => unawaited(_feature.apply(preset)),
      trailing: _feature.selectionMode
          ? Tooltip(
              message: 'Edit ${preset.name}',
              child: ObsidianHudIconButton(
                iconWidget: const EditIcon(),
                size: PageToolbarActionLayout.of(context).iconSize,
                onPressed: _feature.busy ? null : () => unawaited(_openEditor(preset: preset)),
              ),
            )
          : null,
    );
  }

  List<Widget> _contentSlivers(List<ShufflePreset> presets, CustomShuffleSettings settings) {
    final app = _feature.app;
    final local = _feature.target == CustomShuffleTarget.local;
    final error = _feature.error;

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: LocalServerToggle(
                value: local ? ActionScope.local : ActionScope.server,
                onChanged: (value) => _feature.setTarget(
                  value == ActionScope.local ? CustomShuffleTarget.local : CustomShuffleTarget.server,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              local
                  ? 'Local filters stay on this device.'
                  : 'Select saved rules to use for library shuffles on this device. Saving or applying them leaves other devices playing independently.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
            ),
            if (!local && app.shufflePresetsAvailable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ModalActionButton(
                  label: 'Import existing filters',
                  onPressed: _feature.busy ? null : () => unawaited(_feature.importExisting()),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_feature.busy) const LinearProgressIndicator(),
            if (error != null) ...[Text(error), const SizedBox(height: 12)],
          ],
        ),
      ),
      if (local)
        SliverToBoxAdapter(
          child: ObsidianListRow(
            leading: const Icon(PhonoliteIcons.shuffle, color: ObsidianPalette.textMuted),
            title: 'Local custom shuffle',
            subtitle: '${settings.localArtistIds.length} artists · ${settings.localGenres.length} genres',
            trailing: const EditIcon(),
            onTap: () => unawaited(_openEditor(local: true)),
          ),
        )
      else if (!app.shufflePresetsAvailable)
        SliverToBoxAdapter(
          child: Text(
            app.authState.isAuthorized
                ? 'This server needs an update to support saved custom shuffles.'
                : 'Connect to your account to use saved custom shuffles.',
          ),
        )
      else if (presets.isEmpty)
        const SliverToBoxAdapter(child: Text('No saved custom shuffles. Use + to create one.'))
      else
        SliverList.builder(itemCount: presets.length, itemBuilder: (_, index) => _presetRow(presets[index])),
    ];
  }

  @override
  Widget pageContent(BuildContext context, PageAssembler assemble) {
    final app = _feature.app;

    return StreamBuilder<List<ShufflePreset>>(
      stream: app.shufflePresetsStream,
      initialData: app.shufflePresets,
      builder: (context, snapshot) => StreamBuilder<CustomShuffleSettings>(
        stream: app.customShuffleSettingsStream,
        initialData: app.customShuffleSettings,
        builder: (context, settings) {
          final presets = snapshot.data ?? const <ShufflePreset>[];

          return assemble(
            context,
            navbar: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailActionHeader(backLabel: 'Back to settings', onBack: () => Navigator.of(context).pop()),
                const SizedBox(height: 16),
                LibraryHeader(title: 'CUSTOM SHUFFLE', maxLines: 2, trailing: _headerActions(context, presets)),
              ],
            ),
            body: PageBody.slivers(
              padding: const EdgeInsets.all(20),
              slivers: _contentSlivers(presets, settings.data ?? app.customShuffleSettings),
            ),
          );
        },
      ),
    );
  }
}
