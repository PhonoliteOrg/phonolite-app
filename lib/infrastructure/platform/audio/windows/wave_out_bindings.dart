// Native SDK constants retain their documented names.
// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;

import 'package:phonolite_app/data/models/audio/wave_out_values.dart';

export 'package:phonolite_app/data/models/audio/wave_out_values.dart';

const int WAVE_MAPPER = 0xFFFFFFFF;

const int WAVE_FORMAT_PCM = 1;

const int CALLBACK_NULL = 0x00000000;

const int WHDR_DONE = 0x00000001;

const int MMSYSERR_NOERROR = 0;

const int MAXPNAMELEN = 32;

typedef WaveOutOpenNative =
    ffi.Uint32 Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
      ffi.Uint32 uDeviceID,
      ffi.Pointer<WAVEFORMATEX> pwfx,
      ffi.Pointer<ffi.Void> dwCallback,
      ffi.Pointer<ffi.Void> dwInstance,
      ffi.Uint32 fdwOpen,
    );

typedef WaveOutOpenDart =
    int Function(
      ffi.Pointer<ffi.Pointer<ffi.Void>> phwo,
      int uDeviceID,
      ffi.Pointer<WAVEFORMATEX> pwfx,
      ffi.Pointer<ffi.Void> dwCallback,
      ffi.Pointer<ffi.Void> dwInstance,
      int fdwOpen,
    );

typedef WaveOutGetNumDevsNative = ffi.Uint32 Function();

typedef WaveOutGetNumDevsDart = int Function();

typedef WaveOutGetDevCapsWNative =
    ffi.Uint32 Function(ffi.Uint32 uDeviceID, ffi.Pointer<WAVEOUTCAPSW> pwoc, ffi.Uint32 cbwoc);

typedef WaveOutGetDevCapsWDart = int Function(int uDeviceID, ffi.Pointer<WAVEOUTCAPSW> pwoc, int cbwoc);

typedef WaveOutPrepareHeaderNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, ffi.Uint32 cbwh);

typedef WaveOutPrepareHeaderDart = int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef WaveOutWriteNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, ffi.Uint32 cbwh);

typedef WaveOutWriteDart = int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef WaveOutUnprepareHeaderNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, ffi.Uint32 cbwh);

typedef WaveOutUnprepareHeaderDart = int Function(ffi.Pointer<ffi.Void> hwo, ffi.Pointer<WAVEHDR> pwh, int cbwh);

typedef WaveOutCloseNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutCloseDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutResetNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutResetDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutPauseNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutPauseDart = int Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutRestartNative = ffi.Uint32 Function(ffi.Pointer<ffi.Void> hwo);

typedef WaveOutRestartDart = int Function(ffi.Pointer<ffi.Void> hwo);

String utf16ArrayToString(ffi.Array<ffi.Uint16> data) {
  final codes = <int>[];

  for (var i = 0; i < MAXPNAMELEN; i++) {
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
  final WaveOutOpenDart waveOutOpen;
  final WaveOutGetNumDevsDart waveOutGetNumDevs;
  final WaveOutGetDevCapsWDart waveOutGetDevCapsW;
  final WaveOutPrepareHeaderDart waveOutPrepareHeader;
  final WaveOutWriteDart waveOutWrite;
  final WaveOutUnprepareHeaderDart waveOutUnprepareHeader;
  final WaveOutCloseDart waveOutClose;
  final WaveOutResetDart waveOutReset;
  final WaveOutPauseDart waveOutPause;
  final WaveOutRestartDart waveOutRestart;

  WaveOutBindings()
    : waveOutOpen = _lib.lookup<ffi.NativeFunction<WaveOutOpenNative>>('waveOutOpen').asFunction(),
      waveOutGetNumDevs = _lib.lookup<ffi.NativeFunction<WaveOutGetNumDevsNative>>('waveOutGetNumDevs').asFunction(),
      waveOutGetDevCapsW = _lib.lookup<ffi.NativeFunction<WaveOutGetDevCapsWNative>>('waveOutGetDevCapsW').asFunction(),
      waveOutPrepareHeader = _lib
          .lookup<ffi.NativeFunction<WaveOutPrepareHeaderNative>>('waveOutPrepareHeader')
          .asFunction(),
      waveOutWrite = _lib.lookup<ffi.NativeFunction<WaveOutWriteNative>>('waveOutWrite').asFunction(),
      waveOutUnprepareHeader = _lib
          .lookup<ffi.NativeFunction<WaveOutUnprepareHeaderNative>>('waveOutUnprepareHeader')
          .asFunction(),
      waveOutClose = _lib.lookup<ffi.NativeFunction<WaveOutCloseNative>>('waveOutClose').asFunction(),
      waveOutReset = _lib.lookup<ffi.NativeFunction<WaveOutResetNative>>('waveOutReset').asFunction(),
      waveOutPause = _lib.lookup<ffi.NativeFunction<WaveOutPauseNative>>('waveOutPause').asFunction(),
      waveOutRestart = _lib.lookup<ffi.NativeFunction<WaveOutRestartNative>>('waveOutRestart').asFunction();
}
