import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:phonolite_app/data/models/library/source_track_ref.dart';
import 'package:phonolite_app/data/models/library/track_source_match.dart';
import 'package:phonolite_app/data/storage/offline/library/offline_library.dart';

import '../support/offline_library_test_helpers.dart';

const _source = SourceTrackRef(serverBaseUrl: 'https://one.test/api', serverTrackId: 'song');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late OfflineLibraryStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite_playlist_intents_');
    storage = OfflineLibraryStorage(baseDirectory: directory);
  });

  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  Future<OfflineTrackDownload> storeDownload(
    SourceTrackRef source, {
    OfflineDownloadStatus status = OfflineDownloadStatus.downloaded,
  }) async {
    final file = status == OfflineDownloadStatus.downloaded
        ? await offlineTestMediaFile(directory, '${source.serverTrackId}.mp3')
        : null;
    final download = await storage.prepareDownload(
      offlineTestDownload(
        serverBaseUrl: source.serverBaseUrl,
        track: offlineTestTrack(id: source.serverTrackId),
        status: status,
        filePath: file?.path,
      ),
    );

    await storage.upsertDownload(download);

    return download;
  }

  test('saved addition is visible and counted before queueing and survives restart', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    final saved = await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);

    expect(saved.isPending, isTrue);
    expect(saved.isPlayable, isFalse);
    expect(await storage.readLocalPlaylistTracks(playlist.id), isEmpty);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 1);
    expect((await storage.readLocalPlaylists()).single.trackIds, isEmpty);
    await storage.close();
    storage = OfflineLibraryStorage(baseDirectory: directory);

    final restored = (await storage.readLocalPlaylistEntries(playlist.id)).single;
    expect(restored.entryKey, saved.entryKey);
    expect(restored.track.title, 'The Song');
    expect(restored.source, _source);
    expect(await storage.hasDownloadDemand(_source), isTrue);
  });

  test('queue failure remains a normal persisted playlist addition', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await storage.updatePendingPlaylistRequest(_source, OfflineDownloadStatus.failed, error: 'offline');

    final entries = await storage.readPendingPlaylistEntries(serverBaseUrl: _source.serverBaseUrl);
    expect(entries.single.status, OfflineDownloadStatus.failed);
    expect(entries.single.error, 'offline');
    expect((await storage.readLocalPlaylists()).single.pendingTrackSources, [_source]);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 1);
  });

  test('completion promotes one entry in place and manual additions deduplicate', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    final saved = await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    final download = await storeDownload(_source);

    final entries = await storage.readLocalPlaylistEntries(playlist.id);
    expect(entries, hasLength(1));
    expect(entries.single.entryKey, saved.entryKey);
    expect(entries.single.localTrackId, download.localTrackId);
    expect(entries.single.isPlayable, isTrue);
    expect((await storage.readLocalPlaylists()).single.pendingTrackSources, isEmpty);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 1);
  });

  test('removal before completion cannot be undone by a late download', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    final candidates = await storage.removeSourceFromLocalPlaylist(playlist.id, _source);
    expect(candidates, [_source]);
    expect(await storage.hasDownloadDemand(_source), isFalse);
    await storeDownload(_source);

    expect(await storage.readLocalPlaylistEntries(playlist.id), isEmpty);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 0);
  });

  test('unfinished cleanup is allowed only after every playlist demand is released', () async {
    final first = await storage.createLocalPlaylist('First');
    final second = await storage.createLocalPlaylist('Second');
    await storage.addSourceToLocalPlaylist(first.id, offlineTestTrack(id: 'song'), _source);
    await storage.addSourceToLocalPlaylist(second.id, offlineTestTrack(id: 'song'), _source);
    await storeDownload(_source, status: OfflineDownloadStatus.failed);
    await storage.removeSourceFromLocalPlaylist(first.id, _source);

    expect(await storage.canRemoveUnclaimedDownload(_source), isFalse);
    await storage.removeSourceFromLocalPlaylist(second.id, _source);
    expect(await storage.canRemoveUnclaimedDownload(_source), isTrue);
  });

  test('independent download demand and completed files survive playlist removal', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.registerDownloadDemand(_source, ownerKind: 'manual', ownerId: 'download');
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await storeDownload(_source, status: OfflineDownloadStatus.queued);
    await storage.removeSourceFromLocalPlaylist(playlist.id, _source);

    expect(await storage.canRemoveUnclaimedDownload(_source), isFalse);
    await storage.releaseDownloadDemand(_source, ownerKind: 'manual', ownerId: 'download');
    final complete = await storeDownload(_source);
    await storage.addSourceToLocalPlaylist(playlist.id, complete.track, _source);
    await storage.removeSourceFromLocalPlaylist(playlist.id, _source);
    expect(await storage.canRemoveUnclaimedDownload(_source), isFalse);
    expect(await File(complete.filePath!).exists(), isTrue);
  });

  test('same server track ID on another origin remains a separate pending source', () async {
    const other = SourceTrackRef(serverBaseUrl: 'https://two.test/api', serverTrackId: 'song');
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), other);
    await storage.removeSourceFromLocalPlaylist(playlist.id, _source);

    expect((await storage.readLocalPlaylistEntries(playlist.id)).single.source, other);
    expect(await storage.hasDownloadDemand(other), isTrue);
  });

  test('accepted cross-server match reuses completed local identity without queueing', () async {
    const other = SourceTrackRef(serverBaseUrl: 'https://two.test/api', serverTrackId: 'flac-song');
    final download = await storeDownload(_source);
    await storage.saveTrackSourceMatch(
      TrackSourceMatch(
        localTrackId: download.localTrackId!,
        source: other,
        matchKind: 'metadata_strict',
        score: 0.99,
        metadataSignature: 'song',
        verifiedAt: DateTime.now(),
      ),
    );
    final playlist = await storage.createLocalPlaylist('Mix');
    final saved = await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: other.serverTrackId), other);

    expect(saved.localTrackId, download.localTrackId);
    expect(saved.isPlayable, isTrue);
    expect(await storage.hasDownloadDemand(other), isFalse);
    expect((await storage.readDownloads()), hasLength(1));
  });

  test('clear unfinished retains canceled playlist intent without demand to requeue', () async {
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.addSourceToLocalPlaylist(playlist.id, offlineTestTrack(id: 'song'), _source);
    await storeDownload(_source, status: OfflineDownloadStatus.queued);
    await storage.clearUnfinishedDownloads();

    final entry = (await storage.readLocalPlaylistEntries(playlist.id)).single;
    expect(entry.status, OfflineDownloadStatus.canceled);
    expect(entry.isPlayable, isFalse);
    expect(await storage.hasDownloadDemand(_source), isFalse);
    expect(await storage.readDownloads(), isEmpty);
    expect((await storage.readLocalPlaylists()).single.totalTrackCount, 1);
  });

  test('normalization migration preserves local IDs memberships and pending requests', () async {
    final download = await storeDownload(_source);
    final playlist = await storage.createLocalPlaylist('Mix');
    await storage.addSourceToLocalPlaylist(playlist.id, download.track, _source);
    const pending = SourceTrackRef(serverBaseUrl: 'https://two.test/api', serverTrackId: 'pending');
    await storage.addSourceToLocalPlaylist(
      playlist.id,
      offlineTestTrack(id: 'pending', title: 'Another Song'),
      pending,
    );
    final metadata = await storage.metadataRoot();
    await storage.close();
    final database = sqlite3.open(offlineTestJoin(metadata.path, 'phonolite_offline.sqlite'));

    try {
      database.execute("UPDATE tracks SET match_key = 'legacy-key'");
      database.execute("UPDATE metadata SET value = '11' WHERE key = 'schema_version'");
      database.execute("DELETE FROM metadata WHERE key = 'track_match_normalization_v12'");
    } finally {
      database.dispose();
    }

    storage = OfflineLibraryStorage(baseDirectory: directory);
    final restored = (await storage.readLocalPlaylists()).single;
    expect(restored.trackIds, [download.localTrackId]);
    expect(restored.pendingTrackSources, [pending]);
    expect(restored.totalTrackCount, 2);
    expect(await storage.localTrackIdForSource(_source), download.localTrackId);
    final reopened = sqlite3.open(offlineTestJoin(metadata.path, 'phonolite_offline.sqlite'));

    try {
      expect(reopened.select('SELECT match_key FROM tracks').single['match_key'], 'the artist|the album|the song');
      expect(reopened.select("SELECT value FROM metadata WHERE key = 'schema_version'").single['value'], '12');
    } finally {
      reopened.dispose();
    }
  });
}
