import 'dart:io';

import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';
import 'package:phonolite_app/infrastructure/platform/audio/android_audio_devices.dart';
import 'package:phonolite_app/infrastructure/platform/audio/apple/core_audio_devices.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_devices.dart';

/// Lists native devices after the shared system-default choice, in native order.
Future<List<OutputDevice>> listAudioOutputDevices() async {
  final devices = <OutputDevice>[OutputDevice(id: kDefaultOutputDeviceId, name: 'System Default')];

  if (Platform.isWindows) {
    devices.addAll(listWaveOutDevices());
  } else if (Platform.isMacOS) {
    devices.addAll(listCoreAudioDevices());
  } else if (Platform.isAndroid) {
    devices.addAll(await listAndroidAudioDevices());
  }

  return devices;
}
