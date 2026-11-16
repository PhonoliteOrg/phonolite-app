import 'dart:ffi' as ffi;

// Native ABI field layouts preserve SDK names.
// ignore_for_file: non_constant_identifier_names

const int waveOutMaxDeviceNameLength = 32;

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
