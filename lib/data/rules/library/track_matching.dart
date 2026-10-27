import 'dart:convert';

import 'package:phonolite_app/data/models/library/track.dart';

/// Conservative recording comparisons. Format and download quality are separate.
abstract final class TrackMatching {
  static final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _combiningMark = RegExp(r'\p{M}', unicode: true);
  static const Map<String, String> _accentGroups = {
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
    'c': 'çćĉċč',
    'd': 'ďḋḍḏḑḓ',
    'e': 'èéêëēĕėęěȅȇẹẻẽếềểễệ',
    'g': 'ĝğġģǧǵḡ',
    'h': 'ĥȟḣḥḧḩḫ',
    'i': 'ìíîïĩīĭįǐȉȋịỉ',
    'j': 'ĵǰ',
    'k': 'ķǩḱḳḵ',
    'l': 'ĺļľḷḹḻḽ',
    'n': 'ñńņňǹṅṇṉṋ',
    'o': 'òóôõöōŏőǒǫǭȍȏȯȱọỏốồổỗộớờởỡợ',
    'r': 'ŕŗřȑȓṙṛṝṟ',
    's': 'śŝşšșṡṣ',
    't': 'ţťțṫṭṯṱ',
    'u': 'ùúûüũūŭůűųǔǖǘǚǜȕȗụủứừửữự',
    'w': 'ŵẁẃẅẇẉ',
    'y': 'ýÿŷȳẏỳỵỷỹ',
    'z': 'źżžẑẓẕ',
  };
  static const Set<String> _editionWords = {
    'acoustic',
    'demo',
    'edit',
    'instrumental',
    'karaoke',
    'live',
    'mono',
    'remaster',
    'remastered',
    'remix',
    'stereo',
  };

  /// Preserves non-Latin names; unsupported accent differences remain distinct.
  static String normalize(String value) {
    final out = StringBuffer();
    var separating = true;

    for (final rune in value.toLowerCase().runes) {
      var character = String.fromCharCode(rune);

      if (_combiningMark.hasMatch(character)) {
        continue;
      }

      for (final group in _accentGroups.entries) {
        if (group.value.contains(character)) {
          character = group.key;
          break;
        }
      }

      if (_letterOrNumber.hasMatch(character)) {
        out.write(character);
        separating = false;
      } else if (!separating) {
        out.write(' ');
        separating = true;
      }
    }

    return out.toString().trim();
  }

  static String metadataKey(Track track) =>
      [normalize(track.artist), normalize(track.album), normalize(track.title)].join('|');

  static String metadataSignature(Track track) =>
      jsonEncode([metadataKey(track), track.durationMs, track.trackNo, track.discNo]);

  /// Local reuse requires one identity, exact normalized tags and close duration.
  static Track? uniqueLocalCandidate(Track source, Iterable<Track> candidates) {
    if (!_hasIdentity(source)) {
      return null;
    }

    final key = metadataKey(source);
    final matches = <String, Track>{};

    for (final candidate in candidates) {
      if (_hasIdentity(candidate) &&
          metadataKey(candidate) == key &&
          (source.durationMs - candidate.durationMs).abs() <= 2000 &&
          _numbersCompatible(source, candidate)) {
        matches[candidate.localId ?? candidate.id] = candidate;
      }
    }

    return matches.length == 1 ? matches.values.single : null;
  }

  /// Validates a server match without accepting a different recording edition.
  static bool acceptsServerCandidate(Track source, Track candidate) => score(source, candidate) >= 0.94;

  static double score(Track source, Track candidate) {
    if (!_hasIdentity(source) || !_hasIdentity(candidate) || !_editionsCompatible(source, candidate)) {
      return 0;
    }

    final durationDelta = (source.durationMs - candidate.durationMs).abs();

    if (durationDelta > 3000 || !_numbersCompatible(source, candidate)) {
      return 0;
    }

    final titleScore = _ratio(normalize(source.title), normalize(candidate.title));
    final artistScore = _ratio(normalize(source.artist), normalize(candidate.artist));

    if (titleScore < 0.86 || artistScore < 0.82) {
      return 0;
    }

    final albumScore = _ratio(normalize(source.album), normalize(candidate.album));
    final durationScore = 1 - durationDelta / 3000;
    final numberScore =
        (_numberScore(source.trackNo, candidate.trackNo) + _numberScore(source.discNo, candidate.discNo)) / 2;

    return titleScore * 0.45 + artistScore * 0.30 + durationScore * 0.15 + albumScore * 0.07 + numberScore * 0.03;
  }

  static bool _hasIdentity(Track track) {
    final title = normalize(track.title);
    final artist = normalize(track.artist);

    return track.durationMs > 0 &&
        title.isNotEmpty &&
        title != 'unknown' &&
        title != 'unknown title' &&
        artist.isNotEmpty &&
        artist != 'unknown' &&
        artist != 'unknown artist';
  }

  static bool _numbersCompatible(Track left, Track right) =>
      (left.trackNo == null || right.trackNo == null || left.trackNo == right.trackNo) &&
      (left.discNo == null || right.discNo == null || left.discNo == right.discNo);

  static double _numberScore(int? left, int? right) => left == null || right == null ? 0.5 : (left == right ? 1 : 0);

  static bool _editionsCompatible(Track left, Track right) {
    Set<String> editions(Track track) =>
        normalize('${track.title} ${track.album}').split(' ').toSet().intersection(_editionWords);

    final leftEditions = editions(left);
    final rightEditions = editions(right);

    return leftEditions.length == rightEditions.length && leftEditions.containsAll(rightEditions);
  }

  static double _ratio(String left, String right) {
    if (left == right) {
      return 1;
    }

    final a = left.runes.toList(growable: false);
    final b = right.runes.toList(growable: false);

    if (a.isEmpty || b.isEmpty) {
      return 0;
    }

    var previous = List<int>.generate(b.length + 1, (index) => index);

    for (var row = 0; row < a.length; row++) {
      final current = List<int>.filled(b.length + 1, row + 1);

      for (var column = 0; column < b.length; column++) {
        final substitution = previous[column] + (a[row] == b[column] ? 0 : 1);
        final deletion = previous[column + 1] + 1;
        final insertion = current[column] + 1;
        current[column + 1] = [substitution, deletion, insertion].reduce((a, b) => a < b ? a : b);
      }

      previous = current;
    }

    final longest = a.length > b.length ? a.length : b.length;

    return 1 - previous.last / longest;
  }
}
