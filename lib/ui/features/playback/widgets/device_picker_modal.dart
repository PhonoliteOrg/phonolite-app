import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/playback/device_picker_controller.dart';
import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_list_row.dart';
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

  @override
  void initState() {
    super.initState();

    // The controller turns a failed load into its visible error state.
    unawaited(_feature.loadDevices(refresh: true));
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

    return ObsidianModalList(
      itemCount: _feature.devices.length,
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
    );
  }

  @override
  Widget modalContent(BuildContext context) => SizedBox(width: 320, height: 360, child: _deviceContent(context));

  @override
  List<Widget> modalActions(BuildContext context) => [
    ...super.modalActions(context),
    ModalActionButton(label: 'Refresh', onPressed: _feature.loading ? null : () => _feature.loadDevices(refresh: true)),
  ];
}
