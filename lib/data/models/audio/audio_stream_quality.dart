/// The actual rendition, independently of the user's selected streaming mode.
enum AudioStreamQuality {
  original,
  high,
  medium,
  low;

  static AudioStreamQuality? fromBitrate(int bitrateBps) => switch (bitrateBps) {
    160000 => high,
    96000 => medium,
    48000 => low,
    _ => null,
  };

  static AudioStreamQuality? tryParse(Object? value) => switch (value) {
    'original' => original,
    'high' => high,
    'medium' => medium,
    'low' => low,
    _ => null,
  };
}
