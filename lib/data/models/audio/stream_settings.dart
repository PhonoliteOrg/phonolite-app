/// A stream request's encoding choices, compared by their complete values.
class StreamSettings {
  final String mode;
  final String quality;
  final int frameMs;

  const StreamSettings({required this.mode, required this.quality, this.frameMs = 20});

  const StreamSettings.original() : this(mode: 'original', quality: 'source');

  /// Unmodified source bytes delivered through the authenticated QUIC transport.
  bool get isOriginal => mode == 'original';

  @override
  bool operator ==(Object other) =>
      other is StreamSettings &&
      runtimeType == other.runtimeType &&
      mode == other.mode &&
      quality == other.quality &&
      frameMs == other.frameMs;

  @override
  int get hashCode => Object.hash(runtimeType, mode, quality, frameMs);
}
