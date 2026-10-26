import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/playback/server_shuffle_deck.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  test('one complete pass has no repeats, bounded metadata and reloadable Previous history', () async {
    final requested = <int>[];
    final deck = ServerShuffleDeck(
      _page(0, 35),
      load: (offset) async {
        requested.add(offset);
        return _page(offset, 35);
      },
    );
    expect(await deck.initialize(play: true), isTrue);
    final heard = [deck.tracks[deck.queueIndex].id];
    for (var i = 1; i < 35; i++) {
      expect(await deck.move(1), isTrue);
      await deck.prefetch();
      heard.add(deck.tracks[deck.queueIndex].id);
      expect(deck.tracks.length, lessThanOrEqualTo(30));
    }
    expect(heard, List.generate(35, (index) => 'track-$index'));
    expect(await deck.move(1), isFalse);
    expect(requested, [10, 20, 30]);
    for (var i = 0; i < 32; i++) {
      expect(await deck.move(-1), isTrue);
    }
    expect(deck.tracks[deck.queueIndex].id, 'track-2');
    expect(requested.where((offset) => offset == 0), hasLength(1));
    expect(deck.tracks.length, lessThanOrEqualTo(30));
  });

  test('three remaining tracks trigger one refill shared by prefetch and Next', () async {
    final reply = Completer<ShuffleSessionPage>();
    var requests = 0;
    final deck = ServerShuffleDeck(
      _page(0, 20),
      load: (offset) {
        requests++;
        expect(offset, 10);
        return reply.future;
      },
    );
    await deck.initialize(play: true);
    for (var i = 0; i < 6; i++) {
      await deck.prefetch();
      expect(requests, 0);
      await deck.move(1);
    }
    final firstRefill = deck.prefetch();
    final duplicateRefill = deck.prefetch();
    expect(requests, 1);
    for (var i = 0; i < 3; i++) {
      await deck.move(1);
    }
    final next = deck.move(1);
    expect(requests, 1);
    reply.complete(_page(10, 20));
    await Future.wait([firstRefill, duplicateRefill]);
    expect(await next, isTrue);
    expect(deck.position, 10);
    expect(requests, 1);
  });

  test('deleted IDs and empty pages preserve absolute offsets and full-pass boundaries', () async {
    final deleted = {...List.generate(11, (i) => i), ...List.generate(12, (i) => i + 12)};
    final requested = <int>[];
    final deck = ServerShuffleDeck(
      _page(0, 25, deleted: deleted),
      load: (offset) async {
        requested.add(offset);
        return _page(offset, 25, deleted: deleted);
      },
    );
    expect(await deck.initialize(play: true), isTrue);
    expect(deck.position, 11);
    expect(await deck.move(-1), isTrue);
    expect(deck.position, 24);
    expect(await deck.move(-1), isTrue);
    expect(deck.position, 11);
    expect(await deck.move(1), isTrue);
    expect(deck.position, 24);
    expect(await deck.move(1), isFalse);
    expect(requested, containsAll([10, 20]));
  });

  test('an ineligible current track does not skip the first eligible track', () async {
    final deck = ServerShuffleDeck(_page(0, 3), load: (_) async => throw StateError('Unexpected page'));
    expect(await deck.initialize(play: false, currentTrackId: 'outside'), isTrue);
    expect(deck.queueIndex, -1);
    expect(await deck.move(1), isTrue);
    expect(deck.position, 0);
    expect(await deck.move(-1), isTrue);
    expect(deck.position, 2);
  });

  test('empty first pages work when preparing a deck around an ineligible current track', () async {
    final deleted = List.generate(10, (i) => i).toSet();
    final deck = ServerShuffleDeck(_page(0, 11, deleted: deleted), load: (offset) async => _page(offset, 11));
    expect(await deck.initialize(play: false, currentTrackId: 'outside'), isTrue);
    expect(await deck.move(1), isTrue);
    expect(deck.position, 10);
  });

  test('closing a deck discards pending refills and cancels further reads', () async {
    final reply = Completer<ShuffleSessionPage>();
    var requests = 0;
    final deck = ServerShuffleDeck(
      _page(0, 20),
      load: (_) {
        requests++;
        return reply.future;
      },
    );
    await deck.initialize(play: true);
    for (var i = 0; i < 6; i++) {
      await deck.move(1);
    }
    final refill = deck.prefetch();
    deck.close();
    reply.complete(_page(10, 20));
    await refill;
    expect(deck.tracks, isEmpty);
    expect(await deck.move(1), isFalse);
    expect(requests, 1);
  });

  test('a failed refill can retry its immutable offset without advancing the cursor', () async {
    var requests = 0;
    final deck = ServerShuffleDeck(
      _page(0, 11),
      load: (offset) async {
        if (++requests == 1) throw StateError('Temporary failure');
        return _page(offset, 11);
      },
    );
    await deck.initialize(play: true);
    for (var i = 0; i < 9; i++) {
      await deck.move(1);
    }
    await expectLater(deck.move(1), throwsStateError);
    expect(deck.position, 9);
    expect(await deck.move(1), isTrue);
    expect(deck.position, 10);
    expect(requests, 2);
  });

  test('empty and single-track decks terminate and wrap Previous safely', () async {
    final empty = ServerShuffleDeck(_page(0, 0), load: (_) async => throw StateError('Unexpected page'));
    expect(await empty.initialize(play: true), isFalse);
    final single = ServerShuffleDeck(_page(0, 1), load: (_) async => throw StateError('Unexpected page'));
    expect(await single.initialize(play: true), isTrue);
    expect(await single.move(-1), isTrue);
    expect(single.position, 0);
    expect(await single.move(1), isFalse);
  });
}

ShuffleSessionPage _page(int offset, int total, {Set<int> deleted = const {}}) {
  final next = (offset + 10).clamp(0, total);
  final positions = [
    for (var i = offset; i < next; i++)
      if (!deleted.contains(i)) i,
  ];
  return ShuffleSessionPage(
    sessionId: 'deck',
    offset: offset,
    nextOffset: next,
    total: total,
    hasMore: next < total,
    items: positions.map((i) => offlineTestTrack(id: 'track-$i')).toList(),
    itemOffsets: positions,
  );
}
