import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/library/track_source_resolver.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/library/track_match.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/rules/library/track_matching.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';

const _firstOrigin = 'https://first.test/api';
const _secondOrigin = 'https://second.test/api';

void main() {
  test('normalization preserves non-Latin names and folds common accents', () {
    expect(TrackMatching.normalize('Beyoncé — Café!'), 'beyonce cafe');
    expect(TrackMatching.normalize('Beyonce\u0301'), 'beyonce');
    expect(TrackMatching.normalize('東京'), '東京');
    expect(TrackMatching.normalize('大阪'), '大阪');
    expect(TrackMatching.metadataKey(_track(title: '東京')), isNot(TrackMatching.metadataKey(_track(title: '大阪'))));
  });

  test('local reuse requires a unique local identity and compatible duration', () {
    final source = _track(title: 'The Song!');
    final first = _track(id: 'local-one', localId: 'local-one', durationMs: 181900);
    final second = _track(id: 'local-two', localId: 'local-two', durationMs: 180100);

    expect(TrackMatching.uniqueLocalCandidate(source, [first]), same(first));
    expect(TrackMatching.uniqueLocalCandidate(source, [first, second]), isNull);
    expect(TrackMatching.uniqueLocalCandidate(source.copyWith(artist: ''), [first]), isNull);
  });

  test('recording edition changes are not accepted as equivalent', () {
    expect(TrackMatching.acceptsServerCandidate(_track(title: 'The Song (Live)'), _track()), isFalse);
    expect(TrackMatching.acceptsServerCandidate(_track(), _track(album: 'Album (Remastered)')), isFalse);
  });

  test('foreign source IDs do not resolve to matching raw IDs on current server', () {
    final foreign = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'same-id');
    final otherDownload = _download(
      _track(id: 'same-id', localId: 'local-other', origin: _secondOrigin, sourceId: 'same-id'),
      localId: 'local-other',
      origin: _secondOrigin,
    );

    expect(
      TrackSourceResolver.knownServerTrack(foreign, serverBaseUrl: _secondOrigin, downloads: [otherDownload]),
      isNull,
    );
  });

  test('multiple known quality variants remain ambiguous without source provenance', () {
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');
    final variants = [
      for (final id in ['mp3', 'flac'])
        _download(
          _track(id: id, localId: 'local-one', origin: _secondOrigin, sourceId: id),
          localId: 'local-one',
          origin: _secondOrigin,
        ),
    ];

    expect(TrackSourceResolver.knownServerTrack(local, serverBaseUrl: _secondOrigin, downloads: variants), isNull);
  });

  test('local-to-server matching omits foreign ID and persists a verified association', () async {
    final connection = _Connection();
    final saved = <TrackSourceMatch>[];
    final resolver = _resolver(connection, saved: saved);
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');

    final resolved = await resolver.resolveServerTrack(local);

    expect(connection.descriptors.single.serverTrackId, isNull);
    expect(resolved?.id, 'server-match');
    expect(resolved?.localId, 'local-one');
    expect(resolved?.serverBaseUrl, _secondOrigin);
    expect(saved.single.source, const SourceTrackRef(serverBaseUrl: _secondOrigin, serverTrackId: 'server-match'));
    expect(saved.single.metadataSignature, TrackMatching.metadataSignature(local));
  });

  test('server switch discards an in-flight match before saving or reading remote metadata', () async {
    final connection = _Connection();
    final completion = Completer<List<TrackMatchResult>>();
    connection.matchCompletion = completion.future;
    final saved = <TrackSourceMatch>[];
    final resolver = _resolver(connection, saved: saved);
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');
    final resolving = resolver.resolveServerTrack(local);
    await Future<void>.delayed(Duration.zero);
    connection.origin = 'https://third.test/api';
    connection.revision++;
    completion.complete([_match()]);

    expect(await resolving, isNull);
    expect(connection.fetches, isEmpty);
    expect(saved, isEmpty);
  });

  test('temporary failure does not erase a saved association', () async {
    final connection = _Connection()..fetchError = Exception('unreachable');
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');
    final removed = <SourceTrackRef>[];
    final resolver = _resolver(connection, cached: [_cache(local)], removed: removed);

    expect(await resolver.resolveServerTrack(local), isNull);
    expect(removed, isEmpty);
  });

  test('a locally verified source retains the accepted close-duration tolerance', () async {
    final connection = _Connection()..fetchedTrack = _track(id: 'server-match', durationMs: 181900);
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');
    final resolver = _resolver(connection, cached: [_cache(local, matchKind: 'metadata_local_exact')]);

    final resolved = await resolver.resolveServerTrack(local);

    expect(resolved?.id, 'server-match');
    expect(connection.descriptors, isEmpty);
  });

  test('missing saved source is invalidated without accepting an unrelated replacement', () async {
    final connection = _Connection()..fetchError = ApiException(404, 'missing');
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');
    final removed = <SourceTrackRef>[];
    final resolver = _resolver(connection, cached: [_cache(local)], removed: removed);

    expect(await resolver.resolveServerTrack(local), isNull);
    expect(removed.single.serverTrackId, 'server-match');
  });

  test('a server score cannot authorize incompatible fetched metadata', () async {
    final connection = _Connection()..fetchedTrack = _track(id: 'server-match', title: 'The Song (Live)');
    final saved = <TrackSourceMatch>[];
    final resolver = _resolver(connection, saved: saved);
    final local = _track(id: 'local-one', localId: 'local-one', origin: _firstOrigin, sourceId: 'original');

    expect(await resolver.resolveServerTrack(local), isNull);
    expect(saved, isEmpty);
  });
}

TrackSourceResolver _resolver(
  _Connection connection, {
  List<TrackSourceMatch> cached = const [],
  List<TrackSourceMatch>? saved,
  List<SourceTrackRef>? removed,
}) => TrackSourceResolver(
  connection: connection,
  readMatches: (_, _) async => cached,
  saveMatch: (match) async => saved?.add(match),
  removeMatch: (source) async => removed?.add(source),
);

TrackSourceMatch _cache(Track local, {String matchKind = 'metadata_strict'}) => TrackSourceMatch(
  localTrackId: local.localId!,
  source: const SourceTrackRef(serverBaseUrl: _secondOrigin, serverTrackId: 'server-match'),
  matchKind: matchKind,
  score: 0.99,
  metadataSignature: TrackMatching.metadataSignature(local),
  verifiedAt: DateTime.fromMillisecondsSinceEpoch(1),
);

TrackMatchResult _match() => TrackMatchResult(
  localTrackId: 'local-one',
  serverTrackId: 'server-match',
  confidence: 0.99,
  matchKind: 'metadata_strict',
  serverLiked: false,
  serverUpdatedAt: 0,
);

Track _track({
  String id = 'track',
  String? localId,
  String? origin,
  String? sourceId,
  String title = 'The Song',
  String artist = 'Artist',
  String album = 'Album',
  int durationMs = 180000,
}) => Track(
  id: id,
  localId: localId,
  serverBaseUrl: origin,
  serverTrackId: sourceId,
  title: title,
  artist: artist,
  album: album,
  durationMs: durationMs,
  trackNo: 1,
  discNo: 1,
  liked: false,
  inPlaylists: false,
);

OfflineTrackDownload _download(Track track, {required String localId, required String origin}) => OfflineTrackDownload(
  serverBaseUrl: origin,
  track: track,
  localTrackId: localId,
  status: OfflineDownloadStatus.downloaded,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
);

class _Connection extends Fake implements ServerConnection {
  String origin = _secondOrigin;
  int revision = 0;
  final descriptors = <TrackMatchDescriptor>[];
  final fetches = <String>[];
  Future<List<TrackMatchResult>>? matchCompletion;
  Track? fetchedTrack;
  Object? fetchError;

  @override
  String get baseUrl => origin;

  @override
  String? get token => 'token';

  @override
  int get sessionRevision => revision;

  @override
  Future<List<TrackMatchResult>> matchTracks(List<TrackMatchDescriptor> tracks) async {
    descriptors.addAll(tracks);

    return matchCompletion ?? [_match()];
  }

  @override
  Future<Track> fetchTrackById(String id) async {
    fetches.add(id);
    final error = fetchError;

    if (error != null) {
      throw error;
    }

    return fetchedTrack ?? _track(id: id);
  }
}
