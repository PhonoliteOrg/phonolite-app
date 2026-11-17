import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/library/track_matching.dart';

void main() {
  Track track(String id, {int durationMs = 180000, String? localId}) => Track(
    id: id,
    localId: localId,
    title: 'The Song',
    artist: 'The Artist',
    album: 'The Album',
    durationMs: durationMs,
    liked: false,
    inPlaylists: false,
  );

  test('a local candidate matches within two seconds of the source duration', () {
    final source = track('server-1');

    for (final delta in const [-2000, 0, 2000]) {
      final candidate = track('local-1', durationMs: 180000 + delta);

      expect(TrackMatching.uniqueLocalCandidate(source, [candidate]), same(candidate), reason: '$delta ms');
    }
    for (final delta in const [-2001, 2001]) {
      expect(
        TrackMatching.uniqueLocalCandidate(source, [track('local-1', durationMs: 180000 + delta)]),
        isNull,
        reason: '$delta ms',
      );
    }
  });

  test('a local candidate is chosen only when exactly one identity matches', () {
    final source = track('server-1');
    final first = track('local-1', localId: 'identity-1');
    final copy = track('local-1-copy', localId: 'identity-1', durationMs: 180500);
    final second = track('local-2', localId: 'identity-2');

    expect(TrackMatching.uniqueLocalCandidate(source, [first, copy]), isNotNull);
    expect(TrackMatching.uniqueLocalCandidate(source, [first, second]), isNull);
    expect(TrackMatching.uniqueLocalCandidate(source, const []), isNull);
  });
}
