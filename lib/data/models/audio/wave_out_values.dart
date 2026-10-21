import 'dart:ffi' as ffi;

// Native ABI field layouts preserve SDK names.
// ignore_for_file: non_constant_identifier_names

const int waveOutMaxDeviceNameLength = 32;

final class WAVEFORMATEX extends ffi.Struct {
  @ffi.Uint16()
  external int wFormatTag;
  @ffi.Uint16()
  external int nChannels;
  @ffi.Uint32()
  external int nSamplesPerSec;
  @ffi.Uint32()
  external int nAvgBytesPerSec;
  @ffi.Uint16()
  external int nBlockAlign;
  @ffi.Uint16()
  external int wBitsPerSample;
  @ffi.Uint16()
  external int cbSize;
}

final class WAVEOUTCAPSW extends ffi.Struct {
  @ffi.Uint16()
  external int wMid;
  @ffi.Uint16()
  external int wPid;
  @ffi.Uint32()
  external int vDriverVersion;
  @ffi.Array<ffi.Uint16>(waveOutMaxDeviceNameLength)
  external ffi.Array<ffi.Uint16> szPname;
  @ffi.Uint32()
  external int dwFormats;
  @ffi.Uint16()
  external int wChannels;
  @ffi.Uint16()
  external int wReserved1;
  @ffi.Uint32()
  external int dwSupport;
}

final class WAVEHDR extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> lpData;
  @ffi.Uint32()
  external int dwBufferLength;
  @ffi.Uint32()
  external int dwBytesRecorded;
  @ffi.IntPtr()
  external int dwUser;
  @ffi.Uint32()
  external int dwFlags;
  @ffi.Uint32()
  external int dwLoops;
  external ffi.Pointer<WAVEHDR> lpNext;
  @ffi.IntPtr()
  external int reserved;
}

class WaveBuffer {
  final ffi.Pointer<WAVEHDR> header;
  final ffi.Pointer<ffi.Int16> data;
  final int sampleCount;

  WaveBuffer({required this.header, required this.data, required this.sampleCount});
}
