import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/rules/library/track_matching.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

import '../support/offline_library_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late OfflineLibraryStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite_track_identity_');
    storage = OfflineLibraryStorage(baseDirectory: directory);
  });

  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  test('metadata changes on a known source retain its local identity', () async {
    final original = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'same-source', title: 'Original title'),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(original);
    final updated = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'same-source', title: 'Corrected title', durationMs: 190000),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(updated.localTrackId, original.localTrackId);
  });

  test('a colliding raw source ID from another server does not establish equivalence', () async {
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'same-path-hash', title: 'First song'),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(first);
    final second = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://second.test/api',
        track: offlineTestTrack(id: 'same-path-hash', title: 'Unrelated song'),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(second.localTrackId, isNot(first.localTrackId));
  });

  test('matching metadata on distinct sources can reuse one local identity', () async {
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'mp3-source', artist: 'Beyoncé'),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(first);
    final second = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://second.test/api',
        track: offlineTestTrack(id: 'flac-source', artist: 'Beyonce', durationMs: 181900),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(second.localTrackId, first.localTrackId);
  });

  test('ambiguous local candidates create a distinct identity rather than picking the first', () async {
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'first', durationMs: 180000),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(first);
    final second = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'second', durationMs: 184000),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(second);
    final ambiguous = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://second.test/api',
        track: offlineTestTrack(id: 'third', durationMs: 182000),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(ambiguous.localTrackId, isNot(first.localTrackId));
    expect(ambiguous.localTrackId, isNot(second.localTrackId));
  });

  test('non-Latin names remain distinct in persisted local identities', () async {
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'first', title: '東京'),
        status: OfflineDownloadStatus.queued,
      ),
    );
    await storage.upsertDownload(first);
    final second = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://second.test/api',
        track: offlineTestTrack(id: 'second', title: '大阪'),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(second.localTrackId, isNot(first.localTrackId));
  });

  test('adding a second-server equivalent reuses a downloaded recording before queueing', () async {
    final file = await offlineTestMediaFile(directory, 'first.mp3');
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original', artist: 'Beyoncé'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(first);
    final playlist = await storage.createLocalPlaylist('Local mix');
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'equivalent');
    final entry = await storage.addSourceToLocalPlaylist(
      playlist.id,
      offlineTestTrack(id: 'equivalent', artist: 'Beyonce', title: 'The Song!', durationMs: 181900),
      source,
    );

    expect(entry.isPending, isFalse);
    expect(entry.localTrackId, first.localTrackId);
    expect(await storage.findLocalIdForSource(source), first.localTrackId);
    expect(await storage.hasDownloadDemand(source), isFalse);
    expect(await storage.readDownloads(), hasLength(1));
    expect(await storage.readPendingPlaylistEntries(), isEmpty);
    final matches = await storage.readServerTrackMatches(source.serverBaseUrl, first.localTrackId!);
    expect(matches.single.matchKind, 'metadata_local_exact');
  });

  test('membership preflight recognizes a second server without adding entries or downloading', () async {
    final file = await offlineTestMediaFile(directory, 'local.mp3');
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original', artist: 'Beyoncé'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(first);
    final playlist = await storage.createLocalPlaylist('Local mix');
    await storage.addLocalTrackToPlaylist(playlist.id, first.localTrackId!);
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'equivalent');

    final resolved = await storage.resolveDownloadedLocalSource(
      offlineTestTrack(id: 'equivalent', artist: 'Beyonce', title: 'The Song!'),
      source,
    );

    expect(resolved, first.localTrackId);
    expect(await storage.readDownloads(), hasLength(1));
    expect(await storage.readDownloadDemandSources(), isEmpty);
    expect(await storage.readPendingPlaylistEntries(), isEmpty);
    expect(await storage.readLocalPlaylistEntries(playlist.id), hasLength(1));
    expect((await storage.readLocalPlaylists()).single.trackIds, [first.localTrackId]);
  });

  test('ambiguous downloaded recordings do not satisfy another source implicitly', () async {
    final localIds = <String>{};

    for (final duration in [180000, 184000]) {
      final file = await offlineTestMediaFile(directory, '$duration.mp3');
      final download = await storage.prepareDownload(
        offlineTestDownload(
          serverBaseUrl: 'https://first.test/api',
          track: offlineTestTrack(id: '$duration', durationMs: duration),
          filePath: file.path,
        ),
      );
      await storage.upsertDownload(download);
      localIds.add(download.localTrackId!);
    }

    final playlist = await storage.createLocalPlaylist('Local mix');
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'unresolved');
    final entry = await storage.addSourceToLocalPlaylist(
      playlist.id,
      offlineTestTrack(id: 'unresolved', durationMs: 182000),
      source,
    );

    expect(localIds, hasLength(2));
    expect(entry.isPending, isTrue);
    expect(entry.localTrackId, isNull);
    expect(await storage.findLocalIdForSource(source), isNull);
    expect(await storage.hasDownloadDemand(source), isTrue);
  });

  test('a deleted downloaded file cannot satisfy another source without downloading', () async {
    final file = await offlineTestMediaFile(directory, 'missing.mp3');
    final first = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(first);
    await file.delete();
    final playlist = await storage.createLocalPlaylist('Local mix');
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'replacement');
    final entry = await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'replacement'), source);

    expect(entry.isPending, isTrue);
    expect(await storage.hasDownloadDemand(source), isTrue);
    expect(await storage.findLocalIdForSource(source), isNull);
  });

  test('membership preflight invalidates a matcher-only link when source metadata changes incompatibly', () async {
    final file = await offlineTestMediaFile(directory, 'original.mp3');
    final local = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(local);
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'replaced-path');
    expect(
      await storage.resolveDownloadedLocalSource(offlineTestTrack(id: source.serverTrackId), source),
      local.localTrackId,
    );

    final changed = await storage.resolveDownloadedLocalSource(
      offlineTestTrack(id: source.serverTrackId, title: 'An unrelated recording'),
      source,
    );

    expect(changed, isNull);
    expect(await storage.findLocalIdForSource(source), isNull);
    expect(await storage.readServerTrackMatches(source.serverBaseUrl, local.localTrackId!), isEmpty);
    expect(await storage.readDownloads(), hasLength(1));
    expect(await file.exists(), isTrue);
  });

  test('local addition validates a stale matcher-only link without requiring a prior preflight', () async {
    final file = await offlineTestMediaFile(directory, 'original.mp3');
    final local = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(local);
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'replaced-path');
    await storage.saveTrackSourceMatch(
      TrackSourceMatch(
        localTrackId: local.localTrackId!,
        source: source,
        matchKind: 'metadata_strict',
        score: 0.99,
        metadataSignature: TrackMatching.metadataSignature(local.track),
        verifiedAt: DateTime.now(),
      ),
    );
    final playlist = await storage.createLocalPlaylist('Local mix');
    await storage.addLocalTrackToPlaylist(playlist.id, local.localTrackId!);

    final added = await storage.addSourceToLocalPlaylist(
      playlist.id,
      offlineTestTrack(id: source.serverTrackId, title: 'The Song (Live)'),
      source,
    );

    expect(added.isPending, isTrue);
    expect(added.localTrackId, isNull);
    expect(await storage.findLocalIdForSource(source), isNull);
    expect(await storage.readLocalPlaylistEntries(playlist.id), hasLength(2));
    expect((await storage.readLocalPlaylists()).single.trackIds, [local.localTrackId]);
    expect(await storage.hasDownloadDemand(source), isTrue);
  });

  test('a real downloaded-source identity remains stable when displayed source metadata changes', () async {
    final file = await offlineTestMediaFile(directory, 'original.mp3');
    const source = SourceTrackRef(serverBaseUrl: 'https://first.test/api', serverTrackId: 'original');
    final local = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: source.serverBaseUrl,
        track: offlineTestTrack(id: source.serverTrackId),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(local);

    final resolved = await storage.resolveDownloadedLocalSource(
      offlineTestTrack(id: source.serverTrackId, title: 'A corrected title', durationMs: 190000),
      source,
    );

    expect(resolved, local.localTrackId);
    expect(await storage.readDownloads(), hasLength(1));
    expect(await file.exists(), isTrue);
  });

  test('manual download preparation also rejects an incompatible matcher-only association', () async {
    final file = await offlineTestMediaFile(directory, 'original.mp3');
    final local = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: 'https://first.test/api',
        track: offlineTestTrack(id: 'original'),
        filePath: file.path,
      ),
    );
    await storage.upsertDownload(local);
    const source = SourceTrackRef(serverBaseUrl: 'https://second.test/api', serverTrackId: 'replaced-path');
    await storage.resolveDownloadedLocalSource(offlineTestTrack(id: source.serverTrackId), source);

    final prepared = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: source.serverBaseUrl,
        track: offlineTestTrack(id: source.serverTrackId, title: 'An unrelated recording'),
        status: OfflineDownloadStatus.queued,
      ),
    );

    expect(prepared.localTrackId, isNot(local.localTrackId));
    expect(await storage.findLocalIdForSource(source), isNull);
    expect(await storage.readServerTrackMatches(source.serverBaseUrl, local.localTrackId!), isEmpty);
    expect(await storage.readDownloads(), hasLength(1));
    expect(await file.exists(), isTrue);
  });
}
