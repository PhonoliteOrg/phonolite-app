import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/playback/shuffle_preset_editor_controller.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/features/playback/widgets/custom_shuffle_filter_editor.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_editor_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class ShufflePresetEditorModal extends StatefulWidget {
  final AppController app;
  final ShufflePreset? preset;
  final bool local;

  const ShufflePresetEditorModal({super.key, required this.app, this.preset, this.local = false});

  @override
  State<ShufflePresetEditorModal> createState() => _ShufflePresetEditorModalState();
}

class _ShufflePresetEditorModalState extends State<ShufflePresetEditorModal>
    with ControllerBinding<ShufflePresetEditorModal> {
  late final ShufflePresetEditorController _feature = bindController(
    ShufflePresetEditorController(widget.app, preset: widget.preset, local: widget.local),
  );
  late final TextEditingController _nameController = TextEditingController(text: widget.preset?.name ?? '');

  @override
  void initState() {
    super.initState();

    _nameController.addListener(_handleNameChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();

    super.dispose();
  }

  void _handleNameChanged() => setState(() {});

  Future<void> _submit({bool saveCopy = false}) async {
    final saved = await _feature.submit(_nameController.text, saveCopy: saveCopy);

    if (mounted && saved) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _reload() async {
    final latest = await _feature.reloadLatest();

    if (mounted && latest != null) {
      _nameController.text = latest.name;
    }
  }

  Widget _buildEditor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - ObsidianModalScope.insetsOf(context).horizontal).clamp(0.0, 760.0).toDouble();
    final listHeight = (size.height * 0.5).clamp(180.0, 420.0).toDouble();
    final name = _nameController.text.trim();
    final canSave =
        !_feature.saving &&
        _feature.sessionValid &&
        (widget.local || (name.isNotEmpty && name.length <= ShufflePresetEditorController.maxNameLength));
    final error = _feature.error;

    return PopScope(
      canPop: !_feature.saving,
      child: ObsidianEditorDialog(
        title: Text(
          widget.local
              ? 'Local custom shuffle'
              : (widget.preset == null ? 'Create custom shuffle' : 'Edit custom shuffle'),
        ),
        width: width,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.local) ...[
              Text('Name', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              ObsidianTextField(
                controller: _nameController,
                hintText: 'Custom shuffle name',
                enabled: !_feature.saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),
              const SizedBox(height: 6),
              Text(
                '${_nameController.text.length}/${ShufflePresetEditorController.maxNameLength}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ObsidianPalette.textMuted),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              widget.local
                  ? 'These filters apply only to downloaded music on this device.'
                  : 'Saved rules sync to your account. Select a preset from the list to use it on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.textMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: listHeight,
              child: AbsorbPointer(
                absorbing: _feature.saving,
                child: CustomShuffleFilterEditor(controller: _feature),
              ),
            ),
            if (!_feature.sessionValid) ...[
              const SizedBox(height: 12),
              const Text('The signed-in account changed. Close this editor and reopen it to continue.'),
            ] else if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ObsidianPalette.gold)),
            ],
          ],
        ),
        actions: [
          ModalActionButton(label: 'Cancel', onPressed: _feature.saving ? null : () => Navigator.of(context).pop()),
          if (_feature.conflict) ...[
            ModalActionButton(
              label: 'Reload',
              onPressed: !_feature.saving && _feature.sessionValid ? () => unawaited(_reload()) : null,
            ),
            ModalActionButton(label: 'Save copy', onPressed: canSave ? () => unawaited(_submit(saveCopy: true)) : null),
          ] else
            ModalActionButton(
              label: _feature.saving ? 'Saving' : 'Save',
              onPressed: canSave ? () => unawaited(_submit()) : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildEditor);
}
