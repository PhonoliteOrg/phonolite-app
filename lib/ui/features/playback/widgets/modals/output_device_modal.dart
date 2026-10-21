import 'dart:async';

import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/app_scope.dart';
import 'package:phonolite_app/ui/features/playback/widgets/device_picker_modal.dart';

Future<void> playbackShowDevicePicker(BuildContext context) async {
  final controller = AppScope.of(context);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DevicePickerModal(
      fetchDevices: (refresh) => controller.listOutputDevices(refresh: refresh),
      selectedId: controller.outputDeviceId,
      onSelected: (device) => controller.selectOutputDevice(device),
    ),
  );
}
