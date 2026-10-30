/// Decoded source format before any operating-system or device conversion.
class AudioFileFormat {
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final Duration duration;

  /// Exact audible frames per channel after codec delay/padding removal.
  /// Null means the container supplies no trustworthy sample-accurate length.
  final int? playableFrames;

  const AudioFileFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.duration,
    this.playableFrames,
  });
}
