import 'dart:typed_data';

/// A nonblocking connection owned and polled by the audio worker isolate.
abstract interface class PulseAudioStream {
  void open({required int sampleRate, required int channels, required int bitsPerSample});

  /// Pumps pending protocol messages; false means connection/flush is pending.
  bool poll();

  /// Copies as many complete frames as the server accepts, or returns zero.
  int write(Uint8List bytes);

  void flush();
  void setVolume(double value);
  void setPaused(bool paused);
  int get playedSamples;
  bool get isIdle;
  void close();
}
