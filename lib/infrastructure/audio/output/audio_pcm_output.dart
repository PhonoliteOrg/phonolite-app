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
