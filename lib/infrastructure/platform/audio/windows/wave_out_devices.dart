import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:phonolite_app/data/models/playback/output_device.dart';
import 'package:phonolite_app/infrastructure/platform/audio/windows/wave_out_bindings.dart';

List<OutputDevice> listWaveOutDevices() {
  final bindings = WaveOutBindings();
  final count = bindings.waveOutGetNumDevs();
  final devices = <OutputDevice>[];

  for (var index = 0; index < count; index++) {
    final caps = calloc<WAVEOUTCAPSW>();

    try {
      final result = bindings.waveOutGetDevCapsW(index, caps, ffi.sizeOf<WAVEOUTCAPSW>());

      if (result == MMSYSERR_NOERROR) {
        final name = utf16ArrayToString(caps.ref.szPname);

        devices.add(OutputDevice(id: index, name: name.isEmpty ? 'Device $index' : name));
      }
    } finally {
      calloc.free(caps);
    }
  }

  return devices;
}
