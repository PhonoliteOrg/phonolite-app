import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_bindings.dart';

List<OutputDevice> listCoreAudioDevices() {
  final bindings = CoreAudioBindings();
  final count = bindings.getOutputDeviceCount();
  final devices = <OutputDevice>[];

  for (var index = 0; index < count; index++) {
    final deviceId = bindings.getOutputDeviceId(index).toUnsigned(32);

    if (deviceId == 0) {
      continue;
    }

    final name = bindings.getOutputDeviceName(deviceId);

    devices.add(OutputDevice(id: deviceId, name: name?.isNotEmpty == true ? name! : 'Device $index'));
  }

  return devices;
}
