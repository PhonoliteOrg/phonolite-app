import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_opus/phonolite_opus.dart';

void main() {
  final candidates = [
    'build/windows/x64/plugins/phonolite_opus/Release/phonolite_opus.dll',
    'build/windows/x64/runner/Release/phonolite_opus.dll',
  ];
  final libraryPath = Platform.isWindows
      ? candidates.where((path) => File(path).existsSync()).firstOrNull
      : null;
  // Load the built decoder DLL only. No Flutter app or audio device is opened.
  if (libraryPath != null) {
    ffi.DynamicLibrary.open(File(libraryPath).absolute.path);
  }
  final skip = libraryPath == null
      ? 'Requires a compiled Windows phonolite_opus.dll.'
      : false;

  test('real decoder reused buffers preserve independent PCM lists', () {
    final decoder = OpusDecoder(sampleRate: 48000, channels: 2);
    addTearDown(decoder.dispose);
    final silence = Uint8List.fromList([0xf8, 0xff, 0xfe]);
    final first = decoder.decode(silence, frameSize: 960);
    expect(first, hasLength(1920));
    first[0] = 12345;

    // A larger requested output capacity grows the native scratch buffer.
    final second = decoder.decode(silence, frameSize: decoder.maxFrameSize);
    expect(second, hasLength(1920));
    second[0] = 23456;
    expect(first[0], 12345);

    // This grows packet storage before native validation rejects the packet.
    final invalid = Uint8List(4096)..fillRange(0, 4096, 0xff);
    expect(() => decoder.decode(invalid), throwsA(isA<OpusException>()));
    expect(first[0], 12345);
    expect(second[0], 23456);
    final recovered = decoder.decode(silence, frameSize: 960);
    expect(recovered, hasLength(1920));
    expect(first[0], 12345);
    expect(second[0], 23456);
    expect(recovered[0], isNot(23456));

    decoder.dispose();
    decoder.dispose();
    expect(first[0], 12345);
    expect(second[0], 23456);
    expect(() => decoder.decode(silence), throwsA(isA<OpusException>()));
  }, skip: skip);

  test('real decoder rejects small and invalid frame sizes and recovers', () {
    final decoder = OpusDecoder(sampleRate: 48000, channels: 2);
    addTearDown(decoder.dispose);
    final silence = Uint8List.fromList([0xf8, 0xff, 0xfe]);
    expect(
      () => decoder.decode(silence, frameSize: 120),
      throwsA(isA<OpusException>().having((error) => error.code, 'code', -2)),
    );
    for (final size in [0, -1, decoder.maxFrameSize + 1]) {
      expect(
        () => decoder.decode(silence, frameSize: size),
        throwsA(isA<OpusException>()),
      );
    }
    expect(() => decoder.decode(Uint8List(0)), throwsA(isA<OpusException>()));
    expect(decoder.decode(silence, frameSize: 960), hasLength(1920));
  }, skip: skip);
}
