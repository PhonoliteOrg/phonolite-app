import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/application/library/offline_artist_metadata_repair_queue.dart';
import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/library/artist_summary.dart';
import 'package:phonolite_app/data/projections/library/offline_library_views.dart';
import 'package:phonolite_app/data/repositories/library/artist_browse_repository.dart';
import 'package:phonolite_app/data/repositories/library/artist_metadata_repository.dart';
import 'package:phonolite_app/data/structures/library/byte_lru_cache.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_response_decoder.dart';

import '../support/offline_library_test_helpers.dart';

Artist _artist(String id, {String? logo, String? summary}) =>
    Artist(id: id, name: 'Artist $id', albumCount: 1, logoRef: logo, summary: summary);

ArtistSummaryPage _page(int offset, {String revision = 'catalogue', String? logo}) => ArtistSummaryPage(
  items: [
    for (var index = offset; index < offset + 60 && index < 5000; index++)
      ArtistSummary(id: '$index', name: 'Artist $index', logoRef: logo),
  ],
  total: 5000,
  nextOffset: offset + 60 < 5000 ? offset + 60 : null,
  browseRevision: revision,
);

void main() {
  test('LRU charges bytes and entries and skips oversized retention', () {
    final cache = ByteLruCache<String, int>(maxBytes: 10, maxEntries: 2, sizeOf: (_, value) => value);
    cache.put('a', 4);
    cache.put('b', 4);
    expect(cache.get('a'), 4);
    cache.put('c', 4);
    expect(cache.get('b'), isNull);
    expect(cache.length, 2);
    expect(cache.bytes, 8);
    cache.put('large', 11);
    expect(cache.length, 2);
    cache.clear();
    expect(cache.bytes, 0);
  });

  test('5000 logical positions survive eviction within the bounded page window', () async {
    final requests = <int>[];
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) async {
        requests.add(offset);

        return _page(offset);
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);

    for (var offset = 0; offset < 5000; offset += 60) {
      await repository.loadIndex(offset);
      expect(repository.current.pages.length, lessThanOrEqualTo(12));
      expect(repository.current.retainedBytes, lessThanOrEqualTo(4 * 1024 * 1024));
    }

    expect(repository.current.indices.length, 5000);
    expect(repository.current.indices[4999], 4999);
    expect(repository.current.at(0), isNull);
    expect(repository.current.at(4999)!.id, '4999');
    await repository.loadIndex(0);
    expect(requests.where((offset) => offset == 0), hasLength(2));
    expect(repository.current.total, 5000);
    expect(repository.current.at(0)!.id, '0');
  });

  test('overlapping page requests share work and unrelated events retain the result', () async {
    final response = Completer<ArtistSummaryPage>();
    var reads = 0;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        reads++;

        return response.future;
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    final first = repository.loadIndex(0);
    final second = repository.loadIndex(4);
    repository.invalidateArtist('not-on-this-page');
    response.complete(_page(0));
    await Future.wait([first, second]);
    expect(reads, 1);
    expect(repository.current.at(0)!.id, '0');
  });

  test('background refresh preserves a deep window until every replacement page is ready', () async {
    final first = Completer<ArtistSummaryPage>();
    final deep = Completer<ArtistSummaryPage>();
    final requests = <({int offset, String? revision})>[];
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        requests.add((offset: offset, revision: revision));

        return offset == 0 ? first.future : deep.future;
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, revision: 'old', logo: 'old.png'));
    repository.retainPage(1200, _page(1200, revision: 'old', logo: 'old.png'));
    final snapshots = <String?>[];
    final subscription = repository.changes.listen((snapshot) => snapshots.add(snapshot.at(1200)?.logoRef));
    addTearDown(subscription.cancel);

    final refresh = repository.refresh();
    expect(repository.refresh(), same(refresh));
    await Future<void>.delayed(Duration.zero);
    expect(repository.current.at(1200)!.logoRef, 'old.png');
    first.complete(_page(0, revision: 'new', logo: 'new.png'));
    await Future<void>.delayed(Duration.zero);
    expect(requests, [(offset: 0, revision: null), (offset: 1200, revision: 'new')]);
    expect(repository.current.revision, 'old');
    expect(repository.current.at(0)!.logoRef, 'old.png');
    expect(repository.current.at(1200)!.logoRef, 'old.png');

    deep.complete(_page(1200, revision: 'new', logo: 'new.png'));
    expect((await refresh)!.browseRevision, 'new');
    await Future<void>.delayed(Duration.zero);
    expect(repository.current.revision, 'new');
    expect(repository.current.at(0)!.logoRef, 'new.png');
    expect(repository.current.at(1200)!.logoRef, 'new.png');
    expect(snapshots, ['new.png']);
  });

  test('a failed window refresh retains every old page and allows a later retry', () async {
    var fail = true;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) async {
        if (fail && offset == 1200) {
          throw StateError('Temporary fetch failure');
        }

        return _page(offset, revision: 'new', logo: 'new.png');
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, revision: 'old', logo: 'old.png'));
    repository.retainPage(1200, _page(1200, revision: 'old', logo: 'old.png'));

    await expectLater(repository.refresh(), throwsStateError);
    expect(repository.current.revision, 'old');
    expect(repository.current.total, 5000);
    expect(repository.current.at(0)!.logoRef, 'old.png');
    expect(repository.current.at(1200)!.logoRef, 'old.png');

    fail = false;
    await repository.refresh();
    expect(repository.current.at(1200)!.logoRef, 'new.png');
  });

  test('a successful empty refresh replaces stale artists', () async {
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) async =>
          ArtistSummaryPage(items: const [], total: 0, browseRevision: 'empty'),
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(1200, _page(1200, revision: 'old'));

    final page = await repository.refresh();
    expect(page!.items, isEmpty);
    expect(repository.current.total, 0);
    expect(repository.current.revision, 'empty');
    expect(repository.current.at(1200), isNull);
  });

  test('a new session fences a staged background refresh and clears the previous account', () async {
    var session = 1;
    final response = Completer<ArtistSummaryPage>();
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) => response.future,
      sessionRevision: () => session,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, revision: 'old'));
    final refresh = repository.refresh();
    await Future<void>.delayed(Duration.zero);
    session++;
    repository.reset();
    expect(repository.current.total, 0);

    response.complete(_page(0, revision: 'new'));
    expect(await refresh, isNull);
    expect(repository.current.total, 0);
    expect(repository.current.pages, isEmpty);
  });

  test('window refresh retries revision conflicts without publishing a mixed catalogue', () async {
    var firstReads = 0;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) async {
        if (offset == 0) {
          firstReads++;

          return _page(offset, revision: firstReads == 1 ? 'superseded' : 'new');
        }

        if (revision == 'superseded') {
          throw ApiException(409, 'catalogue changed');
        }

        return _page(offset, revision: 'new');
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(1200, _page(1200, revision: 'old'));

    final refreshed = await repository.refresh();
    expect(firstReads, 2);
    expect(refreshed!.browseRevision, 'new');
    expect(repository.current.at(1200)!.id, '1200');
    expect(repository.current.pages.values.map((page) => page.browseRevision), everyElement('new'));
  });

  test('staged refreshes stay within read admission and retain the bounded window', () async {
    var active = 0;
    var peak = 0;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;

        return _page(offset, revision: 'new');
      },
      sessionRevision: () => 1,
      maxPages: 3,
      concurrency: 2,
    );
    addTearDown(repository.close);
    for (final offset in [600, 1200, 1800]) {
      repository.retainPage(offset, _page(offset, revision: 'old'));
    }

    await repository.refresh();
    expect(peak, lessThanOrEqualTo(2));
    expect(repository.current.pages.length, 3);
    expect(repository.current.at(1800)!.id, '1800');
    expect(repository.current.retainedBytes, lessThanOrEqualTo(4 * 1024 * 1024));
  });

  test('missing visible pages wait for the staged revision and share their queued work', () async {
    final first = Completer<ArtistSummaryPage>();
    final requests = <({int offset, String? revision})>[];
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        requests.add((offset: offset, revision: revision));

        return offset == 0 ? first.future : Future.value(_page(offset, revision: 'new'));
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, revision: 'old'));
    final refresh = repository.refresh();
    await Future<void>.delayed(Duration.zero);
    final visible = repository.loadIndex(60);
    expect(repository.loadIndex(61), same(visible));
    expect(requests, [(offset: 0, revision: null)]);
    expect(repository.current.revision, 'old');

    first.complete(_page(0, revision: 'new'));
    await refresh;
    await visible;
    expect(requests, [(offset: 0, revision: null), (offset: 60, revision: 'new')]);
    expect(repository.current.at(60)!.id, '60');
  });

  test('metadata committed while staging cannot be replaced by an older response', () async {
    final response = Completer<ArtistSummaryPage>();
    var reads = 0;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        reads++;

        return reads == 1 ? response.future : Future.value(_page(offset, logo: 'new.png'));
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, logo: 'old.png'));
    final refresh = repository.refresh();
    await Future<void>.delayed(Duration.zero);
    repository.invalidateArtist('0');
    response.complete(_page(0, logo: 'old.png'));
    await refresh;
    expect(reads, 2);
    expect(repository.current.at(0)!.logoRef, 'new.png');
  });

  test('new visible pages replace obsolete queued work instead of waiting behind it', () async {
    final responses = <int, Completer<ArtistSummaryPage>>{};
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) =>
          (responses[offset] = Completer<ArtistSummaryPage>()).future,
      sessionRevision: () => 1,
      concurrency: 1,
      maxQueued: 1,
    );
    addTearDown(repository.close);
    final active = repository.loadIndex(0);
    final obsolete = repository.loadIndex(60);
    final visible = repository.loadIndex(120);
    await obsolete;
    expect(responses.keys, [0]);
    responses[0]!.complete(_page(0));
    await active;
    await Future<void>.delayed(Duration.zero);
    expect(responses.keys, [0, 120]);
    responses[120]!.complete(_page(120));
    await visible;
    expect(repository.current.at(60), isNull);
    expect(repository.current.at(120)!.id, '120');
  });

  test('an artist commit during a page fill refreshes only the affected page', () async {
    final response = Completer<ArtistSummaryPage>();
    var reads = 0;
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        reads++;

        return reads == 1 ? response.future : Future.value(_page(offset, logo: 'new.png'));
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    final first = repository.loadIndex(0);
    repository.invalidateArtist('0');
    response.complete(_page(0, logo: 'old.png'));
    await first;
    expect(reads, 2);
    expect(repository.current.at(0)!.logoRef, 'new.png');
  });

  test('old-session pages and detail results cannot enter a new session', () async {
    var session = 1;
    final page = Completer<ArtistSummaryPage>();
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) => page.future,
      sessionRevision: () => session,
    );
    addTearDown(repository.close);
    final pending = repository.loadIndex(0);
    session++;
    page.complete(_page(0));
    await pending;
    expect(repository.current.total, 0);
  });

  test('a late old ordering page cannot roll back a newer revision', () async {
    final oldPage = Completer<ArtistSummaryPage>();
    final repository = ArtistBrowseRepository(
      fetch: ({required limit, required offset, revision}) {
        if (offset == 60) {
          return oldPage.future;
        }

        if (revision == 'old') {
          return Future.error(ApiException(409, 'catalogue changed'));
        }

        return Future.value(_page(offset, revision: 'new'));
      },
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    repository.retainPage(0, _page(0, revision: 'old'));
    final old = repository.loadIndex(60);
    await repository.loadIndex(120);
    expect(repository.current.revision, 'new');
    oldPage.complete(_page(60, revision: 'old'));
    await old;
    expect(repository.current.revision, 'new');
    expect(repository.current.at(60), isNull);
    expect(repository.current.at(120)!.id, '120');
  });

  test('missing artwork cooldown survives repeated visits and expires explicitly', () async {
    var time = DateTime.utc(2026);
    var reads = 0;
    final repository = ArtistMetadataRepository(
      fetch: (id) async {
        reads++;

        return _artist(id);
      },
      sessionRevision: () => 1,
      now: () => time,
    );
    addTearDown(repository.close);

    for (var visit = 0; visit < 10; visit++) {
      await repository.load('missing');
    }

    expect(reads, 1);
    time = time.add(const Duration(seconds: 31));
    await repository.load('missing');
    expect(reads, 2);
  });

  test('detail read admission bounds active and queued work before fetching', () async {
    final responses = <Completer<Artist>>[];
    final repository = ArtistMetadataRepository(
      fetch: (_) {
        final response = Completer<Artist>();
        responses.add(response);

        return response.future;
      },
      sessionRevision: () => 1,
      concurrency: 1,
      maxQueued: 1,
    );
    addTearDown(repository.close);
    final first = repository.load('a');
    final queued = repository.load('b');
    await expectLater(repository.load('c'), throwsStateError);
    expect(repository.activeReads, 1);
    expect(repository.queuedReads, 1);
    expect(responses, hasLength(1));
    responses.first.complete(_artist('a'));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(responses, hasLength(2));
    responses.last.complete(_artist('b'));
    await queued;
    expect(repository.queuedReads, 0);
  });

  test('detail invalidation fences its own fill without starving unrelated artists', () async {
    final pending = <String, Completer<Artist>>{};
    final repository = ArtistMetadataRepository(
      fetch: (id) => (pending[id] = Completer<Artist>()).future,
      sessionRevision: () => 1,
    );
    addTearDown(repository.close);
    final first = repository.load('a');
    final alsoFirst = repository.load('a');
    final other = repository.load('b');
    final rejected = expectLater(first, throwsStateError);
    final alsoRejected = expectLater(alsoFirst, throwsStateError);
    repository.invalidate('a');
    pending['a']!.complete(_artist('a', logo: 'old.png'));
    pending['b']!.complete(_artist('b', logo: 'kept.png'));
    await Future.wait([rejected, alsoRejected]);
    expect((await other).logoRef, 'kept.png');
    expect(repository.contains('a'), isFalse);
    expect(repository.contains('b'), isTrue);
  });

  test('detail entries and overload cooldowns fit one shared memory budget', () async {
    var reads = 0;
    final repository = ArtistMetadataRepository(
      fetch: (id) async {
        reads++;

        if (id == 'busy') {
          throw ApiException(429, 'busy', retryAfter: const Duration(minutes: 2));
        }

        return _artist(id, summary: id == 'oversized' ? 'x' * 5000 : null);
      },
      sessionRevision: () => 1,
      maxBytes: 1600,
      maxEntries: 2,
    );
    addTearDown(repository.close);
    await repository.load('a');
    await repository.load('b');
    await repository.load('oversized');
    expect(repository.contains('oversized'), isFalse);
    await expectLater(repository.load('busy'), throwsA(isA<ApiException>()));
    final before = reads;
    await expectLater(repository.load('busy'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)));
    expect(reads, before);
    expect(repository.retainedEntries, lessThanOrEqualTo(2));
    expect(repository.retainedBytes, lessThanOrEqualTo(1600));
  });

  test('new summary endpoint and safe legacy fallback preserve envelope totals', () async {
    final seen = <String>[];
    final connection = ServerConnection(
      baseUrl: 'https://server.test/api',
      client: MockClient((request) async {
        seen.add(request.url.path);

        if (request.url.path.endsWith('/artist-summaries')) {
          return http.Response('missing', 404);
        }

        return http.Response(
          jsonEncode({
            'items': [_artist('legacy', summary: 'detail-only biography').toJson()],
            'total': 5000,
          }),
          200,
        );
      }),
    );
    final first = await connection.fetchArtistSummariesPage();
    final second = await connection.fetchArtistSummariesPage(offset: 60);
    expect(seen.where((path) => path.endsWith('/artist-summaries')), hasLength(1));
    expect(first.total, 5000);
    expect(first.items.single.toArtist().summary, isNull);
    expect(second.nextOffset, 61);
  });

  test('Retry-After supports seconds and dates without retrying before the hint', () {
    const decoder = ApiResponseDecoder();
    final now = DateTime.utc(2026, 10, 25, 12);
    expect(decoder.retryAfter(http.Response('', 429, headers: {'retry-after': '12'})), const Duration(seconds: 12));
    expect(
      decoder.retryAfter(http.Response('', 503, headers: {'retry-after': 'Sun, 25 Oct 2026 12:01:00 GMT'}), now: now),
      const Duration(minutes: 1),
    );
    expect(decoder.retryAfter(http.Response('', 503, headers: {'retry-after': 'bad'})), isNull);
  });

  test('downloaded summary observations reuse prepared metadata and membership', () {
    final group = offlineArtistGroups([offlineTestTrack(id: 'download')]).single;
    expect(group.toArtist(), same(group.toArtist()));
    expect(group.tracksForArtist, same(group.tracksForArtist));
    expect(group.toArtist().albumCount, 1);
    expect(() => group.tracksForArtist.clear(), throwsUnsupportedError);
  });

  testWidgets('offscreen downloaded artist repairs coalesce and remain sequential on overflow', (tester) async {
    final seen = <String>[];
    final blocked = Completer<void>();
    final downloaded = ['a', 'b', 'c', 'd'];
    final queue = OfflineArtistMetadataRepairQueue(
      repair: (id) async {
        seen.add(id);

        if (seen.length == 1) {
          await blocked.future;
        }
      },
      isDownloaded: downloaded.contains,
      downloadedArtistAt: (index) => index < downloaded.length ? downloaded[index] : null,
      maxQueued: 2,
    );
    addTearDown(queue.close);
    queue.schedule('not-downloaded');
    queue.schedule('a');
    queue.schedule('a');
    await tester.pump(const Duration(milliseconds: 300));
    expect(seen, ['a']);
    queue.schedule('b');
    queue.schedule('c');
    queue.schedule('d');
    expect(queue.queued, 2);
    expect(seen, ['a']);
    blocked.complete();
    await tester.pump();
    expect(seen.toSet(), downloaded.toSet());
    expect(queue.running, isFalse);
  });
}
