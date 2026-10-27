/// Decoded source format before any operating-system or device conversion.
class AudioFileFormat {
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final Duration duration;

  const AudioFileFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.duration,
  });
}
