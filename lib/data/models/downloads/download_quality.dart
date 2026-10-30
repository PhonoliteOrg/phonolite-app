/// Immutable encoding profiles shared by download requests and saved jobs.
enum DownloadQuality {
  spaceSaver('opus_64', 'Space saver', 64),
  standard('opus_96', 'Standard', 96),
  high('opus_128', 'High', 128),
  veryHigh('opus_192', 'Very high', 192),
  original('original', 'Original', null);

  final String wireValue;
  final String label;
  final int? bitrateKbps;

  const DownloadQuality(this.wireValue, this.label, this.bitrateKbps);

  bool get isOriginal => this == original;

  /// Decimal MB of audio per hour at the target rate, excluding artwork.
  double? get megabytesPerHour => bitrateKbps == null ? null : bitrateKbps! * 0.45;

  static DownloadQuality fromWireValue(Object? value) => tryFromWireValue(value) ?? original;

  static DownloadQuality? tryFromWireValue(Object? value) {
    for (final quality in values) {
      if (quality.wireValue == value) return quality;
    }

    return null;
  }
}
