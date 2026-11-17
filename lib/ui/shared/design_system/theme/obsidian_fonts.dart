/// Font families bundled through the app's font manifest.
///
/// Styles name these families directly so text never depends on runtime font
/// fetching. Only the weights the manifest declares render without synthesis.
abstract final class ObsidianFonts {
  /// Display family for headings, labels and numerals.
  static const String display = 'Rajdhani';

  /// Body family for running text.
  static const String body = 'Poppins';
}
