import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/auth_storage.dart';
import 'package:phonolite_app/entities/server_connection.dart';
import 'package:phonolite_app/entities/server_trust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  setUp(() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          if (call.method == 'read') return values[key];
          if (call.method == 'write') values[key] = args['value'] as String;
          if (call.method == 'delete') values.remove(key);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null),
  );
  final trust = ServerTrust(
    spki: 'ab' * 32,
    opaqueKey: base64Encode(List.filled(32, 1)),
  );
  test(
    'server entry accepts an IP and port and rejects insecure schemes',
    () async {
      final connection = ServerConnection(
        baseUrl: 'https://127.0.0.1:3000/api/v1',
      );
      expect(
        await connection.resolveBaseUrl('192.168.1.20:3000'),
        'https://192.168.1.20:3000/api/v1',
      );
      expect(
        await connection.resolveBaseUrl('[::1]:3000'),
        'https://[::1]:3000/api/v1',
      );
      for (final input in [
        'http://host:3000',
        'https://user:password@host:3000',
        'https://host:3000/prefix',
        'https://host:3000?token=secret',
      ]) {
        await expectLater(connection.resolveBaseUrl(input), throwsException);
      }
    },
  );
  test(
    'a bearer token needs authenticated server trust and is cleared on server change',
    () {
      final connection = ServerConnection(
        baseUrl: 'https://tokens.test:3000/api/v1',
      );
      expect(() => connection.setToken('secret'), throwsStateError);
      connection.setTrust(trust);
      connection.setToken('secret');
      connection.setBaseUrl('https://other.test:3000/api/v1');
      expect(connection.token, isNull);
      expect(() => connection.setToken('secret'), throwsStateError);
    },
  );
  test('pins apply to exactly one HTTPS origin', () {
    ServerTrustRegistry.register('https://pinned.test:3000/api/v1', trust);
    ServerTrustRegistry.validate(Uri.parse('https://pinned.test:3000/library'));
    for (final input in [
      'http://pinned.test:3000',
      'https://pinned.test:3001',
      'https://attacker.test:3000',
    ]) {
      expect(
        () => ServerTrustRegistry.validate(Uri.parse(input)),
        throwsA(isA<HandshakeException>()),
      );
    }
  });
  test(
    'API transport blocks cross-server and plaintext requests before opening sockets',
    () async {
      final client = pinnedApiClient(() => 'https://pinned.test:3000/api/v1');
      addTearDown(client.close);
      await expectLater(
        Future.sync(
          () => client.get(Uri.parse('https://attacker.test/api/v1')),
        ),
        throwsStateError,
      );
      await expectLater(
        Future.sync(
          () => client.get(Uri.parse('http://pinned.test:3000/api/v1')),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'server trust survives logout independently of the saved session',
    () async {
      const url = 'https://vault.test:3000/api/v1';
      await ServerTrustStore.write(url, trust);
      const storage = AuthStorage();
      await storage.write(
        AuthCredentials(
          baseUrl: url,
          token: 'secret',
          username: 'listener',
          trust: trust,
        ),
      );
      final restored = await storage.read();
      expect(restored?.token, 'secret');
      expect(restored?.trust.spki, trust.spki);
      await storage.clear();
      expect((await ServerTrustStore.read(url))?.opaqueKey, trust.opaqueKey);
      expect(values.containsKey('phonolite.auth.session.v1'), isFalse);
    },
  );
  test('unsupported saved sessions are rejected without conversion', () async {
    const storage = AuthStorage();
    final valid = AuthCredentials(
      baseUrl: 'https://secure.test:3000/api/v1',
      token: 'secret',
      username: 'listener',
      trust: trust,
    ).toJson();
    for (final invalid in [
      {...valid}..remove('profile'),
      {...valid}..remove('trust'),
      {...valid, 'profile': 'unsupported'},
      {...valid, 'baseUrl': 'http://secure.test:3000/api/v1'},
      {...valid, 'token': ''},
      {...valid, 'username': ''},
    ]) {
      final raw = jsonEncode(invalid);
      values['phonolite.auth.session.v1'] = raw;
      expect(await storage.read(), isNull);
      expect(values['phonolite.auth.session.v1'], raw);
    }
  });
  test('only the new secure session key is read or cleared', () async {
    const storage = AuthStorage();
    values['phonolite.session.v1'] = 'unsupported old session';
    expect(await storage.read(), isNull);
    values['phonolite.auth.session.v1'] = '{invalid';
    expect(await storage.read(), isNull);
    await storage.clear();
    expect(values, {'phonolite.session.v1': 'unsupported old session'});
  });
}
