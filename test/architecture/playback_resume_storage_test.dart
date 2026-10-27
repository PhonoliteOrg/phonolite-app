import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/account_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/device_playback_snapshot.dart';
import 'package:phonolite_app/data/models/playback/playback_resume_checkpoint.dart';
import 'package:phonolite_app/data/models/playback/playback_source_context.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/storage/playback/playback_resume_storage.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SettingsFiles files;
  late PlaybackResumeStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phonolite_playback_resume_');
    files = SettingsFiles(directoryProvider: () async => directory);
    storage = PlaybackResumeStorage(files: files);
  });

  tearDown(() async {
    await storage.flush();
    await directory.delete(recursive: true);
  });

  test('reopen preserves local permutation, occurrence cursor, modes and seek', () async {
    final checkpoint = _checkpoint('local-b').copyWith(cursor: 2);
    final original = DevicePlaybackSnapshot(
      checkpoint: checkpoint,
      queueTrackIds: ['local-b', 'local-a', 'local-b', 'local-c'],
      localShuffleMode: ShuffleMode.currentPlaylist,
      serverShuffleMode: ShuffleMode.artist,
      positionMs: 42000,
    );
    await storage.writeLocal(original);

    final reopened = PlaybackResumeStorage(files: files);
    final restored = await reopened.readLocal();

    expect(restored!.toJson(), original.toJson());
    expect(await reopened.readActiveScope(), 'local');
  });

  test('server and immutable user identities have separate caches', () async {
    final accounts = [
      'https://first.test/key-one/user-a',
      'https://first.test/key-one/user-b',
      'https://first.test/key-two/user-a',
      'https://second.test/key-one/user-a',
    ];
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('local')));

    for (final (index, scope) in accounts.indexed) {
      await storage.writeAccount(
        scope,
        AccountPlaybackSnapshot(revision: index + 1, checkpoint: _checkpoint('$index')),
      );
    }

    for (final (index, scope) in accounts.indexed) {
      expect((await storage.readAccount(scope))!.checkpoint!.trackId, '$index');
    }

    expect((await storage.readLocal())!.checkpoint!.trackId, 'local');
    expect(await storage.readActiveScope(), accounts.last);
    expect(await storage.readAccount('https://unknown.test/key/user-a'), isNull);
    expect(directory.listSync().map((file) => file.path).any((path) => path.contains('user-a')), isFalse);
  });

  test('background account refresh does not replace local active authority', () async {
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('local')));
    await storage.writeAccount('server/account', const AccountPlaybackSnapshot(revision: 3), activate: false);

    expect(await storage.readActiveScope(), 'local');
  });

  test('clear retires queued local writes and retains account state', () async {
    await storage.writeAccount(
      'server/account',
      AccountPlaybackSnapshot(revision: 1, checkpoint: _checkpoint('remote')),
    );
    final writes = [
      for (var i = 0; i < 20; i++) storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('local-$i'))),
    ];
    await storage.clearLocal();
    await Future.wait(writes);

    expect(await storage.readLocal(), isNull);
    expect((await storage.readAccount('server/account'))!.checkpoint!.trackId, 'remote');
    expect(await storage.readActiveScope(), 'server/account');
  });

  test('clearing an account neither clears local state nor another account', () async {
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('local')));
    await storage.writeAccount('server/a', const AccountPlaybackSnapshot(revision: 1));
    await storage.writeAccount('server/b', const AccountPlaybackSnapshot(revision: 2));
    await storage.clearAccount('server/a');

    expect(await storage.readAccount('server/a'), isNull);
    expect((await storage.readAccount('server/b'))!.revision, 2);
    expect((await storage.readLocal())!.checkpoint!.trackId, 'local');
    expect(await storage.readActiveScope(), 'server/b');
  });

  test('parallel instances preserve independent keys in the device file', () async {
    final second = PlaybackResumeStorage(files: files);
    await Future.wait([
      storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('local')), activate: false),
      second.writeAccount('server/a', const AccountPlaybackSnapshot(revision: 1)),
    ]);

    expect((await second.readLocal())!.checkpoint!.trackId, 'local');
    expect(await storage.readActiveScope(), 'server/a');
  });

  test('interrupted atomic replacement leaves the previous snapshot readable', () async {
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('before')));
    final blocker = Directory('${directory.path}/playback_resume.json.tmp');
    await blocker.create();

    await expectLater(
      storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('after'))),
      throwsA(isA<FileSystemException>()),
    );
    expect((await storage.readLocal())!.checkpoint!.trackId, 'before');

    await blocker.delete();
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('recovered')));
    expect((await storage.readLocal())!.checkpoint!.trackId, 'recovered');
  });

  test('corrupt snapshots are ignored and an explicit save repairs them', () async {
    final file = await files.resolve('playback_resume.json');
    await file.writeAsString('{interrupted');

    expect(await storage.readLocal(), isNull);
    await storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('fresh')));
    expect((await storage.readLocal())!.checkpoint!.trackId, 'fresh');
  });

  test('future storage versions survive an older app save attempt', () async {
    final file = await files.resolve('playback_resume.json');
    final future = jsonEncode({'schema_version': 99, 'future': 'retained'});
    await file.writeAsString(future);

    expect(await storage.readLocal(), isNull);
    await expectLater(
      storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('older-app'))),
      throwsFormatException,
    );
    expect(await file.readAsString(), future);
  });

  test('future device snapshot versions are retained within the current storage envelope', () async {
    final file = await files.resolve('playback_resume.json');
    final future = jsonEncode({
      'schema_version': 1,
      'local': {'schema_version': 99, 'future': true},
    });
    await file.writeAsString(future);

    expect(await storage.readLocal(), isNull);
    await expectLater(
      storage.writeLocal(DevicePlaybackSnapshot(checkpoint: _checkpoint('older-app'))),
      throwsFormatException,
    );
    expect(await file.readAsString(), future);
  });
}

PlaybackResumeCheckpoint _checkpoint(String trackId) => PlaybackResumeCheckpoint(
  trackId: trackId,
  source: PlaybackSourceContext(kind: 'playlist', id: 'mix'),
  shuffleMode: ShuffleMode.currentPlaylist,
  shuffleContext: PlaybackSourceContext(kind: 'playlist', id: 'mix'),
);
