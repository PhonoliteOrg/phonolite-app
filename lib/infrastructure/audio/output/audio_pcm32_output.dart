import 'dart:async';
import 'dart:typed_data';

import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';

/// Output capability for signed, left-aligned PCM with up to 32 valid bits.
abstract interface class AudioPcm32Output {
  Future<void> writePcm32(Int32List samples);
}

extension AudioPcm32Write on AudioPcmOutput {
  Future<void> writePcm32(Int32List samples) {
    final output = this;

    if (output is AudioPcm32Output) {
      final originalOutput = output as AudioPcm32Output;

      return originalOutput.writePcm32(samples);
    }

    throw UnsupportedError('This audio output cannot preserve the original PCM precision.');
  }
}
