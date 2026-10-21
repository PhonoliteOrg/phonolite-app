import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/downloads/download_manager_controller.dart';
import 'package:phonolite_app/data/models/downloads/download_job.dart';
import 'package:phonolite_app/data/models/downloads/download_status.dart';
import 'package:phonolite_app/data/models/downloads/offline_track_download.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/rules/downloads/download_queue_rules.dart';
import 'package:phonolite_app/data/structures/downloads/offline_download_index.dart';
import 'package:phonolite_app/ui/features/downloads/presentation/download_manager_entries.dart';

Track track(String id, {String? localId, String? serverTrackId, String? artistId, String artist = 'Artist'}) => Track(
  id: id,
  title: id,
  artist: artist,
  artistId: artistId,
  album: 'Album',
  durationMs: 1,
  liked: false,
  inPlaylists: false,
  localId: localId,
  serverTrackId: serverTrackId,
);

OfflineTrackDownload download(
  Track track, {
  String serverBaseUrl = 'https://server',
  String? localTrackId,
  OfflineDownloadStatus status = OfflineDownloadStatus.queued,
  int priority = 0,
}) => OfflineTrackDownload(
  serverBaseUrl: serverBaseUrl,
  track: track,
  localTrackId: localTrackId,
  status: status,
  priority: priority,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('alias indexes preserve first-match precedence and server scoping', () {
    final first = download(
      track('track', localId: 'local', serverTrackId: 'server'),
      localTrackId: 'stored-local',
    );
    final duplicate = download(track('server', localId: 'another'));
    final otherOrigin = download(track('server'), serverBaseUrl: 'https://other');
    final index = OfflineDownloadIndex([first, duplicate, otherOrigin]);

    for (final alias in ['track', 'local', 'server', 'stored-local']) {
      expect(index.findServer('https://server', alias), same(first));
      expect(index.findLocal(alias), same(first));
    }

    expect(index.findServer('https://other', 'server'), same(otherOrigin));
    expect(index.findServer('https://missing', 'server'), isNull);
  });

  test('actor exact keys and facade trimmed keys retain their separate contracts', () {
    final value = download(track(' track ', localId: ' local '), serverBaseUrl: ' https://server ');
    final actor = OfflineDownloadIndex([value]);
    final facade = OfflineDownloadIndex([value], trimServerKeys: true);

    expect(actor.findServer(' https://server ', 'track'), same(value));
    expect(actor.findServer('https://server', 'track'), isNull);
    expect(actor.findServer(' https://server ', ' track '), isNull);
    expect(facade.findServer('https://server', 'track'), same(value));
    expect(facade.findServer(' https://server ', ' track '), same(value));
    expect(actor.findLocal('local'), same(value));
    expect(facade.findLocal(' local '), isNull);
  });

  test('pause eligibility is shared by observed and commanded download states', () {
    const pausable = {
      OfflineDownloadStatus.queued,
      OfflineDownloadStatus.preparing,
      OfflineDownloadStatus.downloading,
      OfflineDownloadStatus.validating,
    };

    for (final status in OfflineDownloadStatus.values) {
      final expected = pausable.contains(status);
      final state = DownloadManagerViewState([download(track('track'), status: status)], []);

      expect(DownloadQueueRules.canPauseDownloadStatus(status), expected, reason: status.name);
      expect(DownloadManagerController.canPauseDownloadStatus(status), expected, reason: status.name);
      expect(state.hasPausable, expected, reason: status.name);
    }
  });

  test('functional groups keep their order while UI owns headings and spacers', () {
    final lower = download(track('lower'), priority: 1);
    final higher = download(track('higher'), priority: 5);
    final paused = download(track('paused'), status: OfflineDownloadStatus.paused);
    final completed = download(track('completed'), status: OfflineDownloadStatus.downloaded);
    final job = OfflineDownloadJob(
      jobId: 'job',
      kind: 'album',
      serverBaseUrl: 'https://server',
      status: OfflineDownloadStatus.paused,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final state = DownloadManagerViewState([lower, paused, completed, higher], [job]);

    expect(state.groups[DownloadSection.queue], [higher, lower]);
    expect(state.groups[DownloadSection.paused], [paused]);
    expect(state.hasPaused, isTrue);
    expect(() => state.groups[DownloadSection.queue]!.clear(), throwsUnsupportedError);
    expect(() => state.jobs.clear(), throwsUnsupportedError);

    final entries = DownloadManagerEntries.build(state);

    expect(entries.map((entry) => entry.kind), [
      DownloadManagerEntryKind.jobHeader,
      DownloadManagerEntryKind.job,
      DownloadManagerEntryKind.spacer,
      DownloadManagerEntryKind.sectionHeader,
      DownloadManagerEntryKind.download,
      DownloadManagerEntryKind.download,
      DownloadManagerEntryKind.spacer,
      DownloadManagerEntryKind.sectionHeader,
      DownloadManagerEntryKind.download,
      DownloadManagerEntryKind.spacer,
    ]);
    expect(entries.where((entry) => entry.title != null).map((entry) => entry.title), ['Queue', 'Paused']);
    expect(entries.where((entry) => entry.kind == DownloadManagerEntryKind.spacer).map((entry) => entry.height), [
      12,
      12,
      12,
    ]);
  });

  test('artwork identity keeps identified artists distinct from fallback names', () {
    expect(track('one', artistId: ' Artist-ID ', artist: 'A').artistArtworkIdentity, 'id:Artist-ID');
    expect(track('two', artistId: '', artist: ' Artist Name ').artistArtworkIdentity, 'name:artist name');
    expect(track('three', artistId: 'artist-id', artist: 'A').artistArtworkIdentity, isNot('id:Artist-ID'));
  });
}
