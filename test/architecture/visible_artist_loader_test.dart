import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/application/library/visible_artist_loader.dart';
import 'package:phonolite_app/data/models/library/artist.dart';

Artist _artist(String id, {String? logo}) => Artist(id: id, name: 'Artist $id', albumCount: 1, logoRef: logo);

void main() {
  testWidgets('bounds requests and drops queued artists that leave the viewport', (tester) async {
    final requests = <String>[];
    final pending = <String, Completer<Artist>>{};
    var changed = 0;
    final loader = VisibleArtistLoader(
      fetch: (id) {
        requests.add(id);
        return (pending[id] = Completer<Artist>()).future;
      },
      watch: (_) => const Stream.empty(),
      onChanged: () => changed++,
    );
    addTearDown(loader.dispose);

    for (var i = 0; i < 20; i++) {
      loader.setVisible(_artist('$i'), true);
    }
    expect(requests, ['0', '1', '2']);
    for (var i = 0; i < 19; i++) {
      loader.setVisible(_artist('$i'), false);
    }
    for (final id in ['0', '1', '2']) {
      pending[id]!.complete(_artist(id, logo: '$id.png'));
    }
    await tester.pump();
    expect(requests, ['0', '1', '2', '19']);
    expect(changed, 0, reason: 'Off-screen responses must not update the page.');
    pending['19']!.complete(_artist('19', logo: '19.png'));
    await tester.pump();
    expect(loader.resolve(_artist('19')).logoRef, '19.png');
    expect(changed, 1);
    loader.setVisible(_artist('19'), false);
    expect(loader.resolve(_artist('19')).logoRef, isNull, reason: 'No off-screen metadata is retained.');
  });

  testWidgets('push enrichment fills the visible tile and cancels follow-up reads', (tester) async {
    final updates = StreamController<Artist>.broadcast(sync: true);
    final pending = Completer<Artist>();
    var requests = 0;
    var changed = 0;
    final loader = VisibleArtistLoader(
      fetch: (_) {
        requests++;
        return pending.future;
      },
      watch: (_) => updates.stream,
      onChanged: () => changed++,
    );
    addTearDown(loader.dispose);
    addTearDown(updates.close);
    loader.setVisible(_artist('bb'), true);
    updates.add(_artist('bb', logo: 'bb.png'));
    // An older GET may complete after the push update; it must not erase art.
    pending.complete(_artist('bb'));
    await tester.pump();
    expect(loader.resolve(_artist('bb')).logoRef, 'bb.png');
    expect(changed, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(requests, 1);
  });

  testWidgets('bounded follow-up reads recover a missed enrichment event', (tester) async {
    var requests = 0;
    final loader = VisibleArtistLoader(
      fetch: (id) async => _artist(id, logo: ++requests == 2 ? 'found.png' : null),
      watch: (_) => const Stream.empty(),
      onChanged: () {},
    );
    addTearDown(loader.dispose);
    loader.setVisible(_artist('artist'), true);
    await tester.pump();
    expect(loader.resolve(_artist('artist')).logoRef, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(loader.resolve(_artist('artist')).logoRef, 'found.png');
    await tester.pump(const Duration(minutes: 1));
    expect(requests, 2);
  });

  testWidgets('unmatched artists stop polling and leaving view cancels timers', (tester) async {
    final requests = <String>[];
    final loader = VisibleArtistLoader(
      fetch: (id) async {
        requests.add(id);
        return _artist(id);
      },
      watch: (_) => const Stream.empty(),
      onChanged: () {},
    );
    addTearDown(loader.dispose);
    loader.setVisible(_artist('stays'), true);
    loader.setVisible(_artist('leaves'), true);
    await tester.pump();
    loader.setVisible(_artist('leaves'), false);
    for (final delay in [2, 5, 10, 60]) {
      await tester.pump(Duration(seconds: delay));
    }
    expect(requests.where((id) => id == 'stays'), hasLength(4));
    expect(requests.where((id) => id == 'leaves'), hasLength(1));
  });

  testWidgets('session resets ignore old reads and never reuse old metadata', (tester) async {
    final pending = <Completer<Artist>>[];
    var changed = 0;
    final loader = VisibleArtistLoader(
      fetch: (_) {
        final result = Completer<Artist>();
        pending.add(result);
        return result.future;
      },
      watch: (_) => const Stream.empty(),
      onChanged: () => changed++,
    );
    addTearDown(loader.dispose);
    loader.setVisible(_artist('same'), true);
    loader.clear();
    loader.setVisible(_artist('same'), true);
    pending.first.complete(_artist('same', logo: 'old-server.png'));
    await tester.pump();
    expect(changed, 0);
    expect(loader.resolve(_artist('same')).logoRef, isNull);
    pending.last.complete(_artist('same', logo: 'new-server.png'));
    await tester.pump();
    expect(loader.resolve(_artist('same')).logoRef, 'new-server.png');
    loader.clear();
    expect(loader.resolve(_artist('same')).logoRef, isNull);
  });

  testWidgets('artists with artwork use their list metadata without another read', (tester) async {
    var requests = 0;
    final loader = VisibleArtistLoader(
      fetch: (id) async {
        requests++;
        return _artist(id);
      },
      watch: (_) => const Stream.empty(),
      onChanged: () {},
    );
    addTearDown(loader.dispose);
    final artist = _artist('ready', logo: 'stored.png');
    loader.setVisible(artist, true);
    await tester.pump(const Duration(minutes: 1));
    expect(requests, 0);
    expect(loader.resolve(artist), same(artist));
  });
}
