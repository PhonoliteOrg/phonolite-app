import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/data/storage/preferences/settings_files.dart';

import '../support/auth_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late AuthStorage storage;
  late Directory temp;
  const sessionKey = 'phonolite.auth.session.v1';
  const savedUrl = 'https://SAVED.test:3000/api';
  const credentials = AuthCredentials(
    baseUrl: savedUrl,
    token: 'saved-token',
    username: 'listener',
    trust: testServerTrust,
  );
  final values = <String, String>{};
  final deleted = <String>[];
  final calls = <String>[];
  final trustKey = ServerTrustStore.keyForServer('https://saved.test:3000/');
  Object? readFailure;
  String? deleteFailureKey;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phonolite_startup_credentials_');
    storage = AuthStorage(files: SettingsFiles(directoryProvider: () async => temp));
    values.clear();
    deleted.clear();
    calls.clear();
    readFailure = null;
    deleteFailureKey = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, (call) async {
      calls.add(call.method);
      if (call.method == 'readAll') {
        if (readFailure != null) throw readFailure!;
        return Map<String, String>.from(values);
      }
      if (call.method == 'delete') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String;
        if (key == deleteFailureKey) throw PlatformException(code: 'delete-failed');
        deleted.add(key);
        values.remove(key);
        return null;
      }
      if (call.method == 'write') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        values[args['key'] as String] = args['value'] as String;
        return null;
      }
      fail('Unexpected secure storage operation: ${call.method}');
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, null);
    await temp.delete(recursive: true);
  });

  test('startup without a saved session removes only app-owned security records', () async {
    values.addAll({
      trustKey: jsonEncode(testServerTrust.toJson()),
      'phonolite.session.v1': 'legacy credentials',
      'phonolite.auth.password.v0': 'obsolete password',
      'phonolite.trust.v2.old': 'unsupported pin',
      'unrelated.key': 'keep',
      'phonolite.preferences': 'keep preference',
    });

    await storage.removeOrphanedCredentials();

    expect(values, {'unrelated.key': 'keep', 'phonolite.preferences': 'keep preference'});
    expect(deleted, hasLength(4));
    expect(calls.where((call) => call == 'readAll'), hasLength(1));
    expect(calls, everyElement(isIn(['readAll', 'delete'])));
  });

  test('a remembered server retains its credentials and normalized identity without a network check', () async {
    final savedSession = jsonEncode(credentials.toJson());
    final savedTrust = jsonEncode(testServerTrust.toJson());
    values.addAll({
      sessionKey: savedSession,
      trustKey: savedTrust,
      ServerTrustStore.keyForServer('https://other.test:3000/api'): savedTrust,
      ServerTrustStore.keyForServer('https://saved.test:8443/api'): savedTrust,
      'phonolite.auth.session.v0': 'unsupported saved session',
      'unrelated.key': 'keep',
    });

    await storage.removeOrphanedCredentials();

    expect(values, {sessionKey: savedSession, trustKey: savedTrust, 'unrelated.key': 'keep'});
    expect(deleted, hasLength(3));
    expect(calls.first, 'readAll');
    expect(calls.where((call) => call == 'readAll'), hasLength(1));
    expect(calls.where((call) => call == 'write'), isEmpty);
  });

  test('startup deletes the legacy credential file and preserves neighboring preferences', () async {
    final legacyCredentials = File('${temp.path}/auth.json');
    final preferences = File('${temp.path}/playback_prefs.json');
    await legacyCredentials.writeAsString('{legacy plaintext credentials}');
    await preferences.writeAsString('{"volume":0.5}');

    await storage.removeOrphanedCredentials();

    expect(await legacyCredentials.exists(), isFalse);
    expect(await preferences.readAsString(), '{"volume":0.5}');
    expect(calls, ['readAll']);
  });

  final invalidSessions = <String, String>{
    'malformed JSON': '{invalid',
    'non-object JSON': '[]',
    'unsupported profile': jsonEncode({...credentials.toJson(), 'profile': 'unsupported'}),
    'missing trust': jsonEncode({...credentials.toJson()}..remove('trust')),
    'whitespace token': jsonEncode({...credentials.toJson(), 'token': ' \t\n '}),
    'malformed server URI': jsonEncode({...credentials.toJson(), 'baseUrl': 'https://[invalid/api'}),
    'invalid server port': jsonEncode({...credentials.toJson(), 'baseUrl': 'https://saved.test:99999/api'}),
    'unsupported server path': jsonEncode({...credentials.toJson(), 'baseUrl': 'https://saved.test/api/v1'}),
  };
  for (final entry in invalidSessions.entries) {
    test('startup clears ${entry.key} and its orphan identity', () async {
      values.addAll({sessionKey: entry.value, trustKey: jsonEncode(testServerTrust.toJson()), 'unrelated.key': 'keep'});

      await storage.removeOrphanedCredentials();

      expect(values, {'unrelated.key': 'keep'});
      expect(deleted, unorderedEquals([sessionKey, trustKey]));
    });
  }

  final invalidPins = <String, String>{
    'malformed': '{invalid',
    'unsupported': '{}',
    'different TLS identity': jsonEncode({...testServerTrust.toJson(), 'spki': 'cd' * 32}),
    'different authentication identity': jsonEncode({...testServerTrust.toJson(), 'opaqueKey': 'other-key'}),
  };
  for (final entry in invalidPins.entries) {
    test('a ${entry.key} redundant pin is repaired from the saved identity', () async {
      final savedSession = jsonEncode(credentials.toJson());
      values.addAll({sessionKey: savedSession, trustKey: entry.value});

      await storage.removeOrphanedCredentials();

      expect(values, {sessionKey: savedSession, trustKey: jsonEncode(testServerTrust.toJson())});
      expect(deleted, isEmpty);
      expect(calls, ['readAll', 'write']);
    });
  }

  test('a saved session restores a missing trust record before connecting', () async {
    final savedSession = jsonEncode(credentials.toJson());
    values[sessionKey] = savedSession;

    await storage.removeOrphanedCredentials();

    expect(values, {sessionKey: savedSession, trustKey: jsonEncode(testServerTrust.toJson())});
    expect(calls, ['readAll', 'write']);
  });

  test('an unreadable vault reports the error without deleting credentials', () async {
    final legacyCredentials = File('${temp.path}/auth.json');
    await legacyCredentials.writeAsString('legacy credentials');
    values[sessionKey] = jsonEncode(credentials.toJson());
    values[trustKey] = jsonEncode(testServerTrust.toJson());
    final before = Map<String, String>.from(values);
    readFailure = PlatformException(code: 'keychain-locked');

    await expectLater(storage.removeOrphanedCredentials(), throwsA(isA<PlatformException>()));

    expect(values, before);
    expect(deleted, isEmpty);
    expect(calls, ['readAll']);
    expect(await legacyCredentials.readAsString(), 'legacy credentials');
  });

  test('an unsuccessful orphan deletion remains visible to startup', () async {
    values[trustKey] = jsonEncode(testServerTrust.toJson());
    deleteFailureKey = trustKey;

    await expectLater(storage.removeOrphanedCredentials(), throwsA(isA<PlatformException>()));

    expect(values.containsKey(trustKey), isTrue);
    expect(deleted, isEmpty);
    expect(calls, ['readAll', 'delete']);
  });
}
