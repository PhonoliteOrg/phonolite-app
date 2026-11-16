import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Copies [samples] into native memory that stays valid until [use] completes.
/// Native outputs retry a full queue with this same copy.
Future<void> withNativePcm(TypedData samples, Future<void> Function(ffi.Pointer<ffi.Uint8> data) use) async {
  final data = calloc<ffi.Uint8>(samples.lengthInBytes);

  try {
    data
        .asTypedList(samples.lengthInBytes)
        .setAll(0, samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes));

    await use(data);
  } finally {
    calloc.free(data);
  }
}
