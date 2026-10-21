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

int scoreLibrarySearch(String query, String candidate) => LibrarySearchQuery(query).score(candidate);

/// Prepares a query once for a catalog scan. Display text is never modified.
class LibrarySearchQuery {
  final String normalized;
  late final String compact;
  late final _SearchTerm _term;
  late final List<String> _tokens;
  late final List<_SearchTerm> _tokenTerms;

  LibrarySearchQuery(String query) : normalized = normalizeLibrarySearch(query) {
    compact = normalized.replaceAll(' ', '');
    _term = _SearchTerm(compact);
    _tokens = normalized.split(' ').where((word) => word.isNotEmpty).toList();
    _tokenTerms = _tokens.map(_SearchTerm.new).toList();
  }

  bool get isEmpty => normalized.isEmpty;

  int score(String candidate) {
    if (isEmpty) {
      return 0;
    }

    final target = normalizeLibrarySearch(candidate);

    if (target.isEmpty) {
      return 0;
    }

    final targetCompact = target.replaceAll(' ', '');

    if (target == normalized) {
      return 100;
    }

    if (targetCompact == compact) {
      return 95;
    }

    if (target.startsWith(normalized)) {
      return 90;
    }

    if (targetCompact.startsWith(compact)) {
      return 85;
    }

    if (target.contains(normalized)) {
      return 80;
    }

    if (targetCompact.contains(compact)) {
      return 75;
    }

    if (_tokens.every(target.contains)) {
      return 70;
    }

    final words = target.split(' ').map((word) => word.runes.toList()).toList();

    // Joining consecutive words handles split/merged words without spelling
    // exceptions. Matching tokens separately also allows mixed metadata fields
    // and queries in a different word order.
    var best = _spanDistance(_term, words);

    if (_tokenTerms.length > 1) {
      var tokenDistance = 0;

      for (final token in _tokenTerms) {
        final distance = _spanDistance(token, words);

        if (distance == null) {
          tokenDistance = -1;
          break;
        }

        tokenDistance += distance;
      }

      if (tokenDistance >= 0 && (best == null || tokenDistance < best)) {
        best = tokenDistance;
      }
    }

    return best == null ? 0 : 60 - best.clamp(0, 5);
  }
}

class _SearchTerm {
  final List<int> letters;
  final Map<int, int> counts = <int, int>{};

  _SearchTerm(String value) : letters = value.runes.toList() {
    for (final letter in letters) {
      counts[letter] = (counts[letter] ?? 0) + 1;
    }
  }
}

int? _spanDistance(_SearchTerm term, List<List<int>> words) {
  final query = term.letters;

  // Bound fuzzy work on pathological metadata/queries; literal matching above
  // still supports arbitrarily long text. Short words must match exactly.
  if (query.isEmpty || query.length > 64) {
    return null;
  }

  final int budget;

  if (query.length < 4) {
    budget = 0;
  } else {
    budget = query.length < 8 ? 1 : 2;
  }

  int? best;

  for (var start = 0; start < words.length; start++) {
    final span = <int>[];
    final counts = <int, int>{};
    var shared = 0;

    for (var end = start; end < words.length; end++) {
      if (span.length + words[end].length > query.length + budget) {
        break;
      }

      span.addAll(words[end]);

      for (final letter in words[end]) {
        final count = (counts[letter] ?? 0) + 1;

        counts[letter] = count;

        if (count <= (term.counts[letter] ?? 0)) {
          shared++;
        }
      }

      if ((query.length - span.length).abs() > budget) {
        continue;
      }

      // A swap preserves counts; each other edit repairs at most one missing
      // letter on each side. This lower bound cannot exclude a valid match.
      final longest = query.length > span.length ? query.length : span.length;

      if (longest - shared > budget) {
        continue;
      }

      final distance = _damerauLevenshtein(query, span);

      if (distance <= budget && (best == null || distance < best)) {
        best = distance;

        if (best == 0) {
          return 0;
        }
      }
    }
  }

  return best;
}

// Unrestricted Damerau–Levenshtein on Unicode scalar values. The last-seen
// positions allow insertions/deletions around a transposition, too.
int _damerauLevenshtein(List<int> left, List<int> right) {
  final infinity = left.length + right.length;
  final matrix = List.generate(left.length + 2, (_) => List<int>.filled(right.length + 2, 0));

  matrix[0][0] = infinity;

  for (var i = 0; i <= left.length; i++) {
    matrix[i + 1][0] = infinity;
    matrix[i + 1][1] = i;
  }

  for (var j = 0; j <= right.length; j++) {
    matrix[0][j + 1] = infinity;
    matrix[1][j + 1] = j;
  }

  final lastSeen = <int, int>{};

  for (var i = 1; i <= left.length; i++) {
    var lastMatch = 0;

    for (var j = 1; j <= right.length; j++) {
      final previousRow = lastSeen[right[j - 1]] ?? 0;
      final previousColumn = lastMatch;
      final cost = left[i - 1] == right[j - 1] ? 0 : 1;

      if (cost == 0) {
        lastMatch = j;
      }

      var value = matrix[i][j] + cost;
      final insertion = matrix[i + 1][j] + 1;
      final deletion = matrix[i][j + 1] + 1;
      final transposition = matrix[previousRow][previousColumn] + (i - previousRow - 1) + 1 + (j - previousColumn - 1);

      if (insertion < value) {
        value = insertion;
      }

      if (deletion < value) {
        value = deletion;
      }

      if (transposition < value) {
        value = transposition;
      }

      matrix[i + 1][j + 1] = value;
    }

    lastSeen[left[i - 1]] = i;
  }

  return matrix[left.length + 1][right.length + 1];
}
