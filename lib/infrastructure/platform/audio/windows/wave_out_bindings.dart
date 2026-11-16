// Native SDK constants retain their documented names.
// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;

import 'package:phonolite_app/data/models/audio/wave_out_values.dart';

export 'package:phonolite_app/data/models/audio/wave_out_values.dart';

const int MMSYSERR_NOERROR = 0;

typedef WaveOutGetNumDevsNative = ffi.Uint32 Function();

typedef WaveOutGetNumDevsDart = int Function();

typedef WaveOutGetDevCapsWNative = ffi.Uint32 Function(
  ffi.Uint32 uDeviceID,
  ffi.Pointer<WAVEOUTCAPSW> pwoc,
  ffi.Uint32 cbwoc,
);

typedef WaveOutGetDevCapsWDart = int Function(int uDeviceID, ffi.Pointer<WAVEOUTCAPSW> pwoc, int cbwoc);

String utf16ArrayToString(ffi.Array<ffi.Uint16> data) {
  final codes = <int>[];

  for (var i = 0; i < waveOutMaxDeviceNameLength; i++) {
    final value = data[i];

    if (value == 0) {
      break;
    }

    codes.add(value);
  }

  return String.fromCharCodes(codes);
}

class WaveOutBindings {
  static final ffi.DynamicLibrary _lib = ffi.DynamicLibrary.open('winmm.dll');
  final WaveOutGetNumDevsDart waveOutGetNumDevs;
  final WaveOutGetDevCapsWDart waveOutGetDevCapsW;

  WaveOutBindings()
    : waveOutGetNumDevs = _lib.lookup<ffi.NativeFunction<WaveOutGetNumDevsNative>>('waveOutGetNumDevs').asFunction(),
      waveOutGetDevCapsW = _lib.lookup<ffi.NativeFunction<WaveOutGetDevCapsWNative>>('waveOutGetDevCapsW').asFunction();
}
