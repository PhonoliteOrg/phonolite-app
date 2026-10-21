import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/settings/settings_controller.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/structures/modals/base_alert_modal.dart';

class StoragePathDialog extends BaseAlertModal {
  final String title;
  final String initialPath;
  final bool isDefault;
  final Future<void> Function(String? path) onSave;

  const StoragePathDialog({
    super.key,
    required this.title,
    required this.initialPath,
    required this.isDefault,
    required this.onSave,
  });

  @override
  State<StoragePathDialog> createState() => SettingsStoragePathDialogState();
}

class SettingsStoragePathDialogState extends BaseAlertModalState<StoragePathDialog> {
  late final StoragePathController _feature = bindController(StoragePathController(widget.onSave));
  late final TextEditingController _controller;

  @override
  bool get modalScrollable => true;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.isDefault ? '' : widget.initialPath);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget modalTitle(BuildContext context) => Text(widget.title);

  Future<void> settingsSave() async {
    final saved = await _feature.save(_controller.text);

    if (mounted && saved) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget modalContent(BuildContext context) {
    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ObsidianTextField(
            controller: _controller,
            label: 'Folder path',
            hintText: widget.initialPath,
            height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
            startPadding: 24,
            cut: 0,
            isDense: true,
            enabled: !_feature.saving,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => settingsSave(),
          ),
          if (_feature.error != null) ...[
            const SizedBox(height: 10),
            Text(
              _feature.error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  @override
  List<Widget> modalActions(BuildContext context) => [
    ModalActionButton(label: 'Close', onPressed: _feature.saving ? null : () => Navigator.of(context).pop()),
    ModalActionButton(label: _feature.saving ? 'Saving' : 'Save', onPressed: _feature.saving ? null : settingsSave),
  ];
}
