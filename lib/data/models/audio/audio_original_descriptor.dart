/// Identity and size of the exact file behind an Auto Opus rendition.
class AudioOriginalDescriptor {
  final String sourceVersion;
  final int totalLength;
  final int durationMs;

  const AudioOriginalDescriptor({required this.sourceVersion, required this.totalLength, required this.durationMs});

  int get averageBitrateBps => totalLength * 8000 ~/ durationMs;

  Map<String, dynamic> get sourceMetadata => {'source_version': sourceVersion, 'total_length': totalLength};

  static AudioOriginalDescriptor? tryParse(Object? value) {
    if (value is! Map) {
      return null;
    }
    final version = value['source_version'];
    final length = value['total_length'];
    final duration = value['duration_ms'];

    if (version is! String || version.isEmpty || length is! int || length <= 0 || duration is! int || duration <= 0) {
      return null;
    }

    return AudioOriginalDescriptor(sourceVersion: version, totalLength: length, durationMs: duration);
  }
}
