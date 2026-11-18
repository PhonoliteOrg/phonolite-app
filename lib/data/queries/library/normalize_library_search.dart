// Keep this algorithm and its conformance vectors aligned with
// phonolite-server/crates/library/src/search/matcher.rs.
final _unicodeSearchCharacter = RegExp(r'^[\p{Alphabetic}\p{N}]$', unicode: true);

String normalizeLibrarySearch(String value) {
  final out = StringBuffer();
  var lastSpace = false;

  // A Unicode property regexp over a whole UTF-16 string is expensive in Dart
  // when even one curly apostrophe is present. Classify ASCII directly and use
  // the Unicode predicate only for non-ASCII scalar values, like Rust does.
  for (final rune in value.toLowerCase().runes) {
    final alphanumeric = rune < 128
        ? (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57)
        : _unicodeSearchCharacter.hasMatch(String.fromCharCode(rune));

    if (alphanumeric) {
      out.writeCharCode(rune);
      lastSpace = false;
    } else if (!lastSpace) {
      out.write(' ');
      lastSpace = true;
    }
  }

  return out.toString().trim();
}
