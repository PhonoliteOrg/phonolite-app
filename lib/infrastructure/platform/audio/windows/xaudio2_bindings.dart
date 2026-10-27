import 'dart:ffi' as ffi;

const int xaudio2Ok = 0;
const int xaudio2QueueFull = 1;

typedef XAudio2OpenNative = ffi.Pointer<ffi.Void> Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef XAudio2OpenDart = ffi.Pointer<ffi.Void> Function(int, int, int);

typedef XAudio2OpenFormatNative = ffi.Pointer<ffi.Void> Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef XAudio2OpenFormatDart = ffi.Pointer<ffi.Void> Function(int, int, int, int, int);
typedef XAudio2CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef XAudio2CloseDart = void Function(ffi.Pointer<ffi.Void>);
typedef XAudio2WriteNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int16>, ffi.Int32);
typedef XAudio2WriteDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int16>, int);

typedef XAudio2Write32Native = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, ffi.Int32);
typedef XAudio2Write32Dart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, int);
typedef XAudio2OperationNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef XAudio2OperationDart = int Function(ffi.Pointer<ffi.Void>);
typedef XAudio2SetVolumeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Float);
typedef XAudio2SetVolumeDart = int Function(ffi.Pointer<ffi.Void>, double);
typedef XAudio2CollectDoneSamplesNative = ffi.Int64 Function(ffi.Pointer<ffi.Void>);
typedef XAudio2CollectDoneSamplesDart = int Function(ffi.Pointer<ffi.Void>);

/// The private Windows output bridge. Creating a player does not load the DLL.
class XAudio2Bindings {
  final XAudio2OpenDart open;
  final XAudio2OpenFormatDart openFormat;
  final XAudio2CloseDart close;
  final XAudio2WriteDart write;
  final XAudio2Write32Dart write32;
  final XAudio2OperationDart flush;
  final XAudio2SetVolumeDart setVolume;
  final XAudio2OperationDart pause;
  final XAudio2OperationDart resume;
  final XAudio2CollectDoneSamplesDart collectDoneSamples;
  final XAudio2OperationDart isIdle;

  XAudio2Bindings() : this._(ffi.DynamicLibrary.open('phonolite_audio_windows.dll'));

  XAudio2Bindings._(ffi.DynamicLibrary library)
    : open = library.lookupFunction<XAudio2OpenNative, XAudio2OpenDart>('phonolite_xaudio_open'),
      openFormat = library.lookupFunction<XAudio2OpenFormatNative, XAudio2OpenFormatDart>(
        'phonolite_xaudio_open_format',
      ),
      close = library.lookupFunction<XAudio2CloseNative, XAudio2CloseDart>('phonolite_xaudio_close'),
      write = library.lookupFunction<XAudio2WriteNative, XAudio2WriteDart>('phonolite_xaudio_write'),
      write32 = library.lookupFunction<XAudio2Write32Native, XAudio2Write32Dart>('phonolite_xaudio_write32'),
      flush = library.lookupFunction<XAudio2OperationNative, XAudio2OperationDart>('phonolite_xaudio_flush'),
      setVolume = library.lookupFunction<XAudio2SetVolumeNative, XAudio2SetVolumeDart>('phonolite_xaudio_set_volume'),
      pause = library.lookupFunction<XAudio2OperationNative, XAudio2OperationDart>('phonolite_xaudio_pause'),
      resume = library.lookupFunction<XAudio2OperationNative, XAudio2OperationDart>('phonolite_xaudio_resume'),
      collectDoneSamples = library.lookupFunction<XAudio2CollectDoneSamplesNative, XAudio2CollectDoneSamplesDart>(
        'phonolite_xaudio_collect_done_samples',
      ),
      isIdle = library.lookupFunction<XAudio2OperationNative, XAudio2OperationDart>('phonolite_xaudio_is_idle');
}
