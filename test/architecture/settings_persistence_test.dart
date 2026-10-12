import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/entities/custom_shuffle_settings.dart';
import 'package:phonolite_app/entities/offline_storage_settings.dart';
import 'package:phonolite_app/entities/playback_preferences.dart';
import 'package:phonolite_app/persistence/settings_files.dart';
import '../support/auth_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secrets = <String, String>{};
  late Directory temp;
  late SettingsFiles files;
  setUp(() async {
    secrets.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          if (call.method == 'read') return secrets[key];
          if (call.method == 'write') secrets[key] = args['value'] as String;
          if (call.method == 'delete') secrets.remove(key);
          return null;
        });
    temp = await Directory.systemTemp.createTemp('phonolite_settings_test_');
    files = SettingsFiles(
      directoryProvider: () async => Directory('${temp.path}/settings'),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'concurrent saves across instances preserve both preference keys',
    () async {
      final first = PlaybackPreferencesStorage(files: files);
      final second = PlaybackPreferencesStorage(files: files);
      final file = await files.resolve(
        'playback_prefs.json',
        createDirectory: true,
      );
      await file.writeAsString(jsonEncode({'future_key': 'kept'}));
      await Future.wait([
        for (var i = 0; i < 20; i++) ...[
          first.writeVolume(0.65),
          second.writeCollectionListMode(true),
        ],
      ]);
      expect(await first.readVolume(), 0.65);
      expect(await second.readCollectionListMode(), isTrue);
      expect(jsonDecode(await file.readAsString())['future_key'], 'kept');
    },
  );

  test('a failed preference write does not block a later save', () async {
    final prefs = PlaybackPreferencesStorage(files: files);
    final file = await files.resolve(
      'playback_prefs.json',
      createDirectory: true,
    );
    final blocker = Directory(file.path);
    await blocker.create();
    await prefs.writeVolume(0.5);
    await blocker.delete();
    await prefs.writeCollectionListMode(true);
    expect(await prefs.readCollectionListMode(), isTrue);
  });

  test(
    'reads do not create directories and stores preserve filenames',
    () async {
      const auth = AuthStorage();
      expect(await auth.read(), isNull);
      expect(await Directory('${temp.path}/settings').exists(), isFalse);
      const credentials = AuthCredentials(
        baseUrl: 'https://server.test',
        token: 'secret',
        username: 'listener',
        trust: testServerTrust,
      );
      await auth.write(credentials);
      expect((await auth.read())!.toJson(), credentials.toJson());
      expect(await (await files.resolve('auth.json')).exists(), isFalse);
      await auth.clear();
      expect(await auth.read(), isNull);
      await auth.clear();
    },
  );

  test('preference updates preserve unrelated keys and clamp volume', () async {
    final preferences = PlaybackPreferencesStorage(files: files);
    final file = await files.resolve(
      'playback_prefs.json',
      createDirectory: true,
    );
    await file.writeAsString(jsonEncode({'future_key': 'kept'}));
    await preferences.writeVolume(3);
    await preferences.writeCollectionListMode(true);
    expect(await preferences.readVolume(), 1);
    expect(await preferences.readCollectionListMode(), isTrue);
    expect(jsonDecode(await file.readAsString())['future_key'], 'kept');
    await file.writeAsString('{invalid');
    expect(await preferences.readVolume(), isNull);
    await preferences.writeVolume(-1);
    expect(await preferences.readVolume(), 0);
  });

  test(
    'shuffle normalization and malformed input defaults survive storage',
    () async {
      final shuffle = CustomShuffleSettingsStorage(files: files);
      await shuffle.write(
        const CustomShuffleSettings(
          artistIds: [' artist ', 'artist'],
          genres: [' ROCK ', 'rock'],
          localArtistIds: ['local'],
          localGenres: [' Jazz '],
        ),
      );
      final read = await shuffle.read();
      expect(read.artistIds, ['artist']);
      expect(read.genres, ['rock']);
      expect(read.localGenres, ['jazz']);
      final file = await files.resolve('shuffle_settings.json');
      await file.writeAsString('[]');
      expect((await shuffle.read()).artistIds, isEmpty);
      await file.writeAsString('{invalid');
      expect((await shuffle.read()).localArtistIds, isEmpty);
    },
  );

  test(
    'managed storage clears saved overrides in the injected location',
    () async {
      final unmanaged = OfflineStorageSettingsStorage(
        files: files,
        usesManagedStoragePaths: () => false,
      );
      await unmanaged.write(
        OfflineStorageSettings(
          metadataDirectory: temp.path,
          downloadsDirectory: temp.path,
        ),
      );
      final managed = OfflineStorageSettingsStorage(
        files: files,
        usesManagedStoragePaths: () => true,
      );
      expect((await managed.readRaw()).metadataDirectory, isNotNull);
      expect((await managed.read()).metadataDirectory, isNull);
      expect((await unmanaged.read()).downloadsDirectory, isNull);
      expect(
        await (await files.resolve('offline_storage.json')).exists(),
        isTrue,
      );
    },
  );

  test(
    'offline writes still propagate failures while auth writes tolerate them',
    () async {
      final blocker = File('${temp.path}/file');
      await blocker.writeAsString('not a directory');
      final blocked = SettingsFiles(
        directoryProvider: () async => Directory(blocker.path),
      );
      await expectLater(
        OfflineStorageSettingsStorage(
          files: blocked,
          usesManagedStoragePaths: () => false,
        ).write(const OfflineStorageSettings()),
        throwsA(isA<FileSystemException>()),
      );
      await const AuthStorage().write(
        const AuthCredentials(
          baseUrl: 'https://server.test',
          token: 'secret',
          username: 'listener',
          trust: testServerTrust,
        ),
      );
      expect(await blocker.readAsString(), 'not a directory');
    },
  );
}
