import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

const int coreAudioQueueFull = -3;

typedef CoreAudioOpenNative =
    ffi.Pointer<ffi.Void> Function(ffi.Int32 sampleRate, ffi.Int32 channels, ffi.Int32 deviceId);

typedef CoreAudioOpenDart = ffi.Pointer<ffi.Void> Function(int sampleRate, int channels, int deviceId);

typedef CoreAudioOpenFormatNative = ffi.Pointer<ffi.Void> Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef CoreAudioOpenFormatDart = ffi.Pointer<ffi.Void> Function(int, int, int, int);

typedef CoreAudioCloseNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioCloseDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioWriteNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void> handle, ffi.Pointer<ffi.Int16> samples, ffi.Int32 sampleCount);

typedef CoreAudioWriteDart =
    int Function(ffi.Pointer<ffi.Void> handle, ffi.Pointer<ffi.Int16> samples, int sampleCount);

typedef CoreAudioWrite32Native = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, ffi.Int32);
typedef CoreAudioWrite32Dart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, int);

typedef CoreAudioSetVolumeNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle, ffi.Float volume);

typedef CoreAudioSetVolumeDart = void Function(ffi.Pointer<ffi.Void> handle, double volume);

typedef CoreAudioPauseNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioPauseDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioResumeNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioResumeDart = void Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioCollectDoneNative = ffi.Int64 Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioCollectDoneDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioIsIdleNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioIsIdleDart = int Function(ffi.Pointer<ffi.Void> handle);

typedef CoreAudioDeviceCountNative = ffi.Int32 Function();

typedef CoreAudioDeviceCountDart = int Function();

typedef CoreAudioDeviceIdNative = ffi.Uint32 Function(ffi.Int32 index);

typedef CoreAudioDeviceIdDart = int Function(int index);

typedef CoreAudioDeviceNameNative =
    ffi.Int32 Function(ffi.Uint32 deviceId, ffi.Pointer<ffi.Char> buffer, ffi.Int32 bufferLen);

typedef CoreAudioDeviceNameDart = int Function(int deviceId, ffi.Pointer<ffi.Char> buffer, int bufferLen);

class CoreAudioBindings {
  static const int _nameBufferLen = 256;

  late final CoreAudioOpenDart open;
  late final CoreAudioOpenFormatDart openFormat;
  late final CoreAudioCloseDart close;
  late final CoreAudioWriteDart write;
  late final CoreAudioWrite32Dart write32;
  late final CoreAudioSetVolumeDart setVolume;
  late final CoreAudioPauseDart pause;
  late final CoreAudioResumeDart resume;
  late final CoreAudioIsIdleDart flush;
  late final CoreAudioCollectDoneDart collectDoneSamples;
  late final CoreAudioIsIdleDart isIdle;
  late final CoreAudioDeviceCountDart getOutputDeviceCount;
  late final CoreAudioDeviceIdDart getOutputDeviceId;
  late final CoreAudioDeviceNameDart _getOutputDeviceName;

  CoreAudioBindings() {
    final lib = ffi.DynamicLibrary.process();

    open = lib.lookup<ffi.NativeFunction<CoreAudioOpenNative>>('phonolite_audio_open').asFunction();
    openFormat = lib.lookupFunction<CoreAudioOpenFormatNative, CoreAudioOpenFormatDart>('phonolite_audio_open_format');
    close = lib.lookup<ffi.NativeFunction<CoreAudioCloseNative>>('phonolite_audio_close').asFunction();
    write = lib.lookup<ffi.NativeFunction<CoreAudioWriteNative>>('phonolite_audio_write').asFunction();
    write32 = lib.lookupFunction<CoreAudioWrite32Native, CoreAudioWrite32Dart>('phonolite_audio_write32');
    setVolume = lib.lookup<ffi.NativeFunction<CoreAudioSetVolumeNative>>('phonolite_audio_set_volume').asFunction();
    pause = lib.lookup<ffi.NativeFunction<CoreAudioPauseNative>>('phonolite_audio_pause').asFunction();
    resume = lib.lookup<ffi.NativeFunction<CoreAudioResumeNative>>('phonolite_audio_resume').asFunction();
    flush = lib.lookup<ffi.NativeFunction<CoreAudioIsIdleNative>>('phonolite_audio_flush').asFunction();
    collectDoneSamples = lib
        .lookup<ffi.NativeFunction<CoreAudioCollectDoneNative>>('phonolite_audio_collect_done_samples')
        .asFunction();
    isIdle = lib.lookup<ffi.NativeFunction<CoreAudioIsIdleNative>>('phonolite_audio_is_idle').asFunction();
    getOutputDeviceCount = lib
        .lookup<ffi.NativeFunction<CoreAudioDeviceCountNative>>('phonolite_audio_get_output_device_count')
        .asFunction();
    getOutputDeviceId = lib
        .lookup<ffi.NativeFunction<CoreAudioDeviceIdNative>>('phonolite_audio_get_output_device_id')
        .asFunction();
    _getOutputDeviceName = lib
        .lookup<ffi.NativeFunction<CoreAudioDeviceNameNative>>('phonolite_audio_get_output_device_name')
        .asFunction();
  }

  String? getOutputDeviceName(int deviceId) {
    final buffer = calloc<ffi.Char>(_nameBufferLen);

    try {
      final result = _getOutputDeviceName(deviceId, buffer, _nameBufferLen);

      if (result != 0) {
        return null;
      }

      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }
}
