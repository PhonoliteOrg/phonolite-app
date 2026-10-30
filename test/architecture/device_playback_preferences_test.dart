import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/storage/preferences/playback_preferences.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late SettingsFiles files;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('phonolite_device_preferences_');
    files = SettingsFiles(directoryProvider: () async => temporary);
  });

  tearDown(() => temporary.delete(recursive: true));

  test('repeat persists locally without losing concurrent volume or list preferences', () async {
    final first = PlaybackPreferencesStorage(files: files);
    final second = PlaybackPreferencesStorage(files: files);
    expect(await first.readRepeatMode(), isNull);
    expect(await first.readGaplessResampling(), isNull);

    await Future.wait([
      first.writeRepeatMode(PlaybackRepeatMode.one),
      second.writeVolume(0.4),
      second.writeCollectionListMode(true),
      first.writeGaplessResampling(true),
    ]);
    expect(await second.readRepeatMode(), PlaybackRepeatMode.one);
    expect(await first.readVolume(), 0.4);
    expect(await first.readCollectionListMode(), isTrue);
    expect(await second.readGaplessResampling(), isTrue);

    await second.writeRepeatMode(PlaybackRepeatMode.off);
    expect(await first.readRepeatMode(), PlaybackRepeatMode.off);
    final file = await files.resolve('playback_prefs.json');
    await file.writeAsString(jsonEncode({'repeat_mode': 'invalid', 'gapless_resampling': 'true'}));
    expect(await first.readRepeatMode(), isNull);
    expect(await first.readGaplessResampling(), isNull);
  });

  test('active server filters are isolated by account and server identity', () async {
    final storage = CustomShuffleSettingsStorage(files: files);
    const first = 'https://server-one.test|pin-one|account-one';
    const second = 'https://server-one.test|pin-one|account-two';
    const otherServer = 'https://server-two.test|pin-two|account-one';

    await storage.writeForAccount(
      first,
      const CustomShuffleSettings(artistIds: ['first'], genres: ['Jazz'], localArtistIds: ['private-local']),
    );
    await storage.writeForAccount(second, const CustomShuffleSettings(artistIds: ['second']));
    expect((await storage.readForAccount(first)).artistIds, ['first']);
    expect((await storage.readForAccount(first)).genres, ['jazz']);
    expect((await storage.readForAccount(first)).localArtistIds, isEmpty);
    expect((await storage.readForAccount(second)).artistIds, ['second']);
    expect((await storage.readForAccount(otherServer)).artistIds, isEmpty);
    expect((await storage.read()).artistIds, isEmpty);

    final names = await temporary.list().map((entry) => entry.uri.pathSegments.last).toList();
    expect(names, hasLength(2));
    expect(names.every((name) => RegExp(r'^shuffle_settings_account_[a-f0-9]{64}\.json$').hasMatch(name)), isTrue);
  });

  test('local saves preserve unscoped server filters for explicit legacy import', () async {
    final storage = CustomShuffleSettingsStorage(files: files);
    await storage.write(
      const CustomShuffleSettings(artistIds: ['legacy-server'], genres: ['Rock'], localArtistIds: ['old-local']),
    );
    await storage.writeLocal(
      const CustomShuffleSettings(
        artistIds: ['must-not-replace-legacy'],
        localArtistIds: ['new-local'],
        localGenres: ['Pop'],
      ),
    );
    await storage.writeForAccount('new-account', const CustomShuffleSettings(artistIds: ['new-server']));

    final legacy = await storage.read();
    expect(legacy.artistIds, ['legacy-server']);
    expect(legacy.genres, ['rock']);
    expect(legacy.localArtistIds, ['new-local']);
    expect(legacy.localGenres, ['pop']);
    expect((await storage.readForAccount('new-account')).artistIds, ['new-server']);
  });

  test('account scopes cannot escape the settings directory or use an absent identity', () async {
    final storage = CustomShuffleSettingsStorage(files: files);
    const scope = '../../private/account';
    await storage.writeForAccount(scope, const CustomShuffleSettings(artistIds: ['safe']));
    expect((await storage.readForAccount(scope)).artistIds, ['safe']);
    expect(await temporary.list().length, 1);
    await expectLater(storage.readForAccount('  '), throwsArgumentError);
  });
}
