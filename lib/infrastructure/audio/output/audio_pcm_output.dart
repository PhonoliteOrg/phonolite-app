import 'dart:async';
import 'dart:typed_data';

const int kDefaultOutputDeviceId = -1;

/// Small, cancellable device queue. flush invalidates every pending write.
abstract class AudioPcmOutput {
  /// Opens the device once. Construction alone never acquires a native handle.
  Future<void> initialize();

  /// Completes after the device and all pending startup work have been released.
  Future<void> dispose();

  Future<void> write(Int16List samples);

  Future<void> flush();

  void setVolume(double value);

  void pause();

  void resume();

  Future<int> collectDoneSamples();

  Future<bool> isIdle();
}

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
