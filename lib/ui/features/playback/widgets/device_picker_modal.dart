import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/playback/device_picker_controller.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/color_opacity.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/structures/modals/base_alert_modal.dart';

class DevicePickerModal extends BaseAlertModal {
  final Future<List<OutputDevice>> Function(bool refresh) fetchDevices;
  final Future<void> Function(OutputDevice device) onSelected;
  final int selectedId;

  const DevicePickerModal({super.key, required this.fetchDevices, required this.onSelected, required this.selectedId});

  @override
  State<DevicePickerModal> createState() => _DevicePickerModalState();
}

class _DevicePickerModalState extends BaseAlertModalState<DevicePickerModal> {
  late final DevicePickerController _feature = bindController(DevicePickerController(widget.fetchDevices));
  late final ScrollController _listController;

  @override
  void initState() {
    super.initState();

    _listController = ScrollController();

    // The controller turns a failed load into its visible error state.
    unawaited(_feature.loadDevices(refresh: true));
  }

  @override
  void dispose() {
    _listController.dispose();

    super.dispose();
  }

  @override
  Widget modalTitle(BuildContext context) => const Text('Select output device');

  Future<void> _selectDevice(BuildContext context, OutputDevice device) async {
    final selected = await _feature.selectDevice(device, widget.onSelected);

    // A dismissed dialog stays mounted through its exit animation; popping then would close the route below.
    if (!selected || !context.mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }

    Navigator.of(context).pop();
  }

  Widget _deviceContent(BuildContext context) {
    if (_feature.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_feature.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _feature.error!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    // The explicit scrollbar keeps its thumb visible; disable the one the
    // desktop scroll behavior would add so only one is drawn.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _listController,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _listController,
          padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
          itemCount: _feature.devices.length,
          separatorBuilder: (context, index) =>
              Divider(height: 1, color: ObsidianPalette.textMuted.withByteOpacity(0.25)),
          itemBuilder: (context, index) {
            final device = _feature.devices[index];
            final isSelected = device.id == widget.selectedId;

            return ObsidianModalListRow(
              title: device.name,
              isSelected: isSelected,
              enabled: !_feature.selecting,
              onTap: () => _selectDevice(context, device),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget modalContent(BuildContext context) => SizedBox(width: 320, height: 360, child: _deviceContent(context));

  @override
  List<Widget> modalActions(BuildContext context) => [
    ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
    ModalActionButton(label: 'Refresh', onPressed: _feature.loading ? null : () => _feature.loadDevices(refresh: true)),
  ];
}
