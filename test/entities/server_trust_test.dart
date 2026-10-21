import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/storage/auth/auth_storage.dart';
import 'package:phonolite_app/data/storage/auth/server_trust_store.dart';
import 'package:phonolite_app/infrastructure/server/server_connection.dart';
import 'package:phonolite_app/data/models/auth/server_trust.dart';
import 'package:phonolite_app/infrastructure/security/server_trust.dart'
    show ServerTrustRegistry, installServerTrustOverrides, pinnedApiClient;
import 'package:phonolite_quic/phonolite_quic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  setUp(() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String;
      if (call.method == 'read') return values[key];
      if (call.method == 'write') values[key] = args['value'] as String;
      if (call.method == 'delete') values.remove(key);
      return null;
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, null),
  );
  final trust = ServerTrust(spki: 'ab' * 32, opaqueKey: base64Encode(List.filled(32, 1)));
  test('server entry accepts an IP and port and rejects insecure schemes', () async {
    final connection = ServerConnection(baseUrl: 'https://127.0.0.1:3000/api');
    expect(await connection.resolveBaseUrl('192.168.1.20:3000'), 'https://192.168.1.20:3000/api');
    expect(await connection.resolveBaseUrl('[::1]:3000'), 'https://[::1]:3000/api');
    for (final input in [
      'http://host:3000',
      'https://user:password@host:3000',
      'https://host:3000/prefix',
      'https://host:3000?token=secret',
    ]) {
      await expectLater(connection.resolveBaseUrl(input), throwsException);
    }
  });
  test('a bearer token needs authenticated server trust and is cleared on server change', () {
    final connection = ServerConnection(baseUrl: 'https://tokens.test:3000/api');
    expect(() => connection.setToken('secret'), throwsStateError);
    connection.setTrust(trust);
    connection.setToken('secret');
    connection.setBaseUrl('https://other.test:3000/api');
    expect(connection.token, isNull);
    expect(() => connection.setToken('secret'), throwsStateError);
  });
  test('connection verification waits for TLS health without granting trust', () async {
    final pending = Completer<void>();
    var calls = 0;
    var completed = false;
    const target = 'https://new-endpoint.test:8443/api';
    final connection = ServerConnection(
      baseUrl: 'https://original-endpoint.test/api',
      serverProbe: ({required host, required port, expectedSpki}) async {
        calls++;
        expect(host, 'new-endpoint.test');
        expect(port, 8443);
        expect(expectedSpki, isNull);
        await pending.future;
      },
    );
    final verification = connection.verifyServerConnection(target).then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(completed, isFalse);
    pending.complete();
    await verification;
    expect(connection.baseUrl, 'https://original-endpoint.test/api');
    expect(connection.token, isNull);
    expect(ServerTrustRegistry.lookup(target), isNull);
    expect(values, isEmpty);
  });

  test('connection verification enforces the stored pin for the entered origin', () async {
    const target = 'https://remembered-endpoint.test:3000/api';
    await ServerTrustStore.write(target, trust);
    var calls = 0;
    final connection = ServerConnection(
      baseUrl: 'https://another-endpoint.test/api',
      serverProbe: ({required host, required port, expectedSpki}) async {
        calls++;
        expect(host, 'remembered-endpoint.test');
        expect(port, 3000);
        expect(expectedSpki, trust.spki);
      },
    );
    await connection.verifyServerConnection(target);
    expect(calls, 1);
    expect(values, hasLength(1));
    expect(ServerTrustRegistry.lookup(target), isNull);
  });

  test('failed connection checks preserve the session and allow retry', () async {
    var calls = 0;
    const original = 'https://active-endpoint.test:3000/api';
    final connection = ServerConnection(
      baseUrl: original,
      serverProbe: ({required host, required port, expectedSpki}) async {
        if (++calls == 1) throw QuicException('Unable to connect to server');
      },
    );
    connection.setTrust(trust);
    connection.setToken('existing-session');
    final revision = connection.sessionRevision;
    await expectLater(
      connection.verifyServerConnection('https://unreachable-endpoint.test:3000'),
      throwsA(
        isA<ServerConnectionCheckException>().having(
          (error) => error.message,
          'message',
          'Unable to connect to server',
        ),
      ),
    );
    expect(connection.baseUrl, original);
    expect(connection.token, 'existing-session');
    expect(connection.sessionRevision, revision);
    await connection.verifyServerConnection('https://unreachable-endpoint.test:3000');
    expect(calls, 2);
  });

  test('changed identity is typed and detection preserves old trust until password sign-in', () async {
    const url = 'https://rotated-endpoint.test:3000/api';
    await ServerTrustStore.write(url, trust);
    final connection = ServerConnection(
      baseUrl: url,
      serverProbe: ({required host, required port, expectedSpki}) async {
        expect(expectedSpki, trust.spki);
        throw ServerIdentityChangedException();
      },
    );
    connection.setTrust(trust);
    connection.setToken('old-session');
    await expectLater(
      connection.verifyServerConnection(url),
      throwsA(
        isA<ServerConnectionCheckException>().having(
          (error) => error.reason,
          'reason',
          ServerConnectionFailure.identityChanged,
        ),
      ),
    );
    expect(await connection.hasServerIdentityChanged(), isTrue);
    expect(connection.trust, trust);
    expect(connection.token, 'old-session');
    expect((await ServerTrustStore.read(url))!.spki, trust.spki);
  });

  test('connection checks time out with a useful error', () async {
    final pending = Completer<void>();
    final connection = ServerConnection(
      baseUrl: 'https://timeout-endpoint.test:3000/api',
      serverProbe: ({required host, required port, expectedSpki}) => pending.future,
    );
    await expectLater(
      connection.verifyServerConnection(connection.baseUrl, timeout: const Duration(milliseconds: 5)),
      throwsA(
        isA<ServerConnectionCheckException>().having(
          (error) => error.reason,
          'reason',
          ServerConnectionFailure.timedOut,
        ),
      ),
    );
    pending.complete();
    expect(connection.token, isNull);
  });

  test('stored and runtime trust share the same origin scope', () async {
    const url = 'https://PIN-SCOPE.test/api';
    final sameOrigin = Uri.parse('https://pin-scope.test:443/another/path');

    expect(ServerTrust.origin(Uri.parse(url)), ServerTrustRegistry.origin(sameOrigin));
    await ServerTrustStore.write(url, trust);

    expect((await ServerTrustStore.read(sameOrigin.toString()))?.spki, trust.spki);
    expect(await ServerTrustStore.read('https://pin-scope.test:8443/api'), isNull);
    expect(ServerTrustRegistry.lookup(url), isNull);
  });

  test('forgetting trust removes one normalized origin and invalidates pending authentication', () async {
    const target = 'https://forget-target.test:3000/api';
    const otherPort = 'https://forget-target.test:3001/api';
    final connection = ServerConnection(baseUrl: target);
    final other = ServerConnection(baseUrl: otherPort);
    connection.setTrust(trust);
    other.setTrust(trust);
    other.setToken('other-session');
    await ServerTrustStore.write(target, trust);
    await ServerTrustStore.write(otherPort, trust);
    final revision = connection.sessionRevision;

    connection.forgetTrust('https://FORGET-TARGET.test:3000/');
    await ServerTrustStore.remove('https://FORGET-TARGET.test:3000/');

    expect(connection.sessionRevision, revision + 1);
    expect(connection.token, isNull);
    expect(connection.trust, isNull);
    expect(await ServerTrustStore.read(target), isNull);
    expect(() => connection.setToken('old-session'), throwsStateError);
    expect((await ServerTrustStore.read(otherPort))?.opaqueKey, trust.opaqueKey);
    expect(other.trust, trust);
    expect(other.token, 'other-session');
  });

  test('forgetting waits for an in-flight trust write so it cannot restore the pin', () async {
    const target = 'https://write-then-forget.test:3000/api';
    final enteredWrite = Completer<void>();
    final finishWrite = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vault, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String;
      if (call.method == 'write') {
        enteredWrite.complete();
        await finishWrite.future;
        values[key] = args['value'] as String;
      }
      if (call.method == 'delete') values.remove(key);
      if (call.method == 'read') return values[key];
      return null;
    });
    final writing = ServerTrustStore.write(target, trust);
    await enteredWrite.future;
    final forgetting = ServerTrustStore.remove(target);
    finishWrite.complete();
    await Future.wait([writing, forgetting]);
    expect(await ServerTrustStore.read(target), isNull);
  });

  test('forgetting clears only a matching remembered session', () async {
    const storage = AuthStorage();
    const target = 'https://saved-forget.test:443/api';
    await storage.write(AuthCredentials(baseUrl: target, token: 'secret', username: 'listener', trust: trust));
    await storage.clearForServer('https://saved-forget.test:3000/api');
    expect((await storage.read())?.token, 'secret');
    await storage.clearForServer('https://SAVED-FORGET.test/');
    expect(await storage.read(), isNull);
  });

  test('invalid endpoint details never run the network check', () async {
    var calls = 0;
    final connection = ServerConnection(
      baseUrl: 'https://validation-endpoint.test:3000/api',
      serverProbe: ({required host, required port, expectedSpki}) async {
        calls++;
      },
    );
    for (final input in [
      '',
      'http://host:3000',
      'https://host:0',
      'https://host:65536',
      'https://user:password@host:3000',
      'https://host:3000/wrong-api',
    ]) {
      await expectLater(connection.verifyServerConnection(input), throwsException);
    }
    expect(calls, 0);
  });
  test('pins apply to exactly one HTTPS origin', () {
    ServerTrustRegistry.register('https://pinned.test:3000/api', trust);
    ServerTrustRegistry.validate(Uri.parse('https://pinned.test:3000/library'));
    for (final input in ['http://pinned.test:3000', 'https://pinned.test:3001', 'https://attacker.test:3000']) {
      expect(() => ServerTrustRegistry.validate(Uri.parse(input)), throwsA(isA<HandshakeException>()));
    }
  });
  test('API transport blocks cross-server and plaintext requests before opening sockets', () async {
    final client = pinnedApiClient(() => 'https://pinned.test:3000/api');
    addTearDown(client.close);
    await expectLater(Future.sync(() => client.get(Uri.parse('https://attacker.test/api'))), throwsStateError);
    await expectLater(Future.sync(() => client.get(Uri.parse('http://pinned.test:3000/api'))), throwsStateError);
  });
  test('API clients retire forgotten TLS pools before reuse after fresh sign-in', () async {
    const url = 'https://api-pool.test:3000/api';
    final clients = <_FakeHttpClient>[];
    final events = <String>[];
    ServerTrustRegistry.register(url, trust);
    final client = pinnedApiClient(
      () => url,
      createHttpClient: (_) {
        final inner = _FakeHttpClient(clients.length, events);
        clients.add(inner);
        return inner;
      },
    );
    addTearDown(client.close);
    addTearDown(() => ServerTrustRegistry.forget(url));
    final requestUrl = Uri.parse('$url/health');

    await expectLater(client.get(requestUrl), throwsA(isA<http.ClientException>()));
    ServerTrustRegistry.forget(url);
    await expectLater(Future.sync(() => client.get(requestUrl)), throwsA(isA<HandshakeException>()));
    ServerTrustRegistry.register(url, trust);
    await expectLater(client.get(requestUrl), throwsA(isA<http.ClientException>()));

    expect(events, ['open:0', 'close:0:true', 'open:1']);
    expect(clients, hasLength(2));
    expect(clients.last.badCertificateCallback, isNotNull);
    expect(clients.last.findProxy!(requestUrl), 'DIRECT');
  });
  test('artwork clients retire replaced TLS pins and retain their configuration', () async {
    const url = 'https://artwork-pool.test:3000/api';
    final clients = <_FakeHttpClient>[];
    final events = <String>[];
    final previousOverrides = HttpOverrides.current;
    ServerTrustRegistry.register(url, trust);
    installServerTrustOverrides(
      createHttpClient: (_) {
        final inner = _FakeHttpClient(clients.length, events);
        clients.add(inner);
        return inner;
      },
    );
    addTearDown(() => HttpOverrides.global = previousOverrides);
    addTearDown(() => ServerTrustRegistry.forget(url));
    final client = HttpClient()
      ..idleTimeout = const Duration(seconds: 8)
      ..connectionTimeout = const Duration(seconds: 3)
      ..maxConnectionsPerHost = 2
      ..autoUncompress = false
      ..userAgent = 'artwork-test';
    addTearDown(() => client.close(force: true));
    final requestUrl = Uri.parse('$url/artwork');

    await expectLater(client.getUrl(requestUrl), throwsA(isA<HttpException>()));
    ServerTrustRegistry.register(url, trust);
    await expectLater(client.getUrl(requestUrl), throwsA(isA<HttpException>()));
    expect(clients, hasLength(1));
    ServerTrustRegistry.register(url, ServerTrust(spki: 'cd' * 32, opaqueKey: trust.opaqueKey));
    await expectLater(client.getUrl(requestUrl), throwsA(isA<HttpException>()));

    expect(events, ['open:0', 'open:0', 'close:0:true', 'open:1']);
    expect(clients.last.idleTimeout, const Duration(seconds: 8));
    expect(clients.last.connectionTimeout, const Duration(seconds: 3));
    expect(clients.last.maxConnectionsPerHost, 2);
    expect(clients.last.autoUncompress, isFalse);
    expect(clients.last.userAgent, 'artwork-test');
    client.close(force: true);
    ServerTrustRegistry.forget(url);
    ServerTrustRegistry.register(url, trust);
    await expectLater(client.getUrl(requestUrl), throwsA(isA<HttpException>()));
    expect(clients, hasLength(2));
  });
  test('a request opened while trust is removed cannot escape on an old TLS connection', () async {
    const url = 'https://pending-pool.test:3000/api';
    final opened = Completer<HttpClientRequest>();
    final events = <String>[];
    final previousOverrides = HttpOverrides.current;
    ServerTrustRegistry.register(url, trust);
    var count = 0;
    installServerTrustOverrides(
      createHttpClient: (_) => _FakeHttpClient(count++, events)..pendingRequest = opened.future,
    );
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final opening = client.getUrl(Uri.parse('$url/artwork'));
    final rejected = expectLater(opening, throwsA(isA<HandshakeException>()));

    ServerTrustRegistry.forget(url);
    final request = _FakeHttpClientRequest();
    opened.complete(request);
    await rejected;

    expect(events, ['open:0', 'close:0:true']);
    expect(request.abortError, isA<HandshakeException>());
  });
  test('clearing a remembered session alone does not remove stored server trust', () async {
    const url = 'https://vault.test:3000/api';
    await ServerTrustStore.write(url, trust);
    const storage = AuthStorage();
    await storage.write(AuthCredentials(baseUrl: url, token: 'secret', username: 'listener', trust: trust));
    final restored = await storage.read();
    expect(restored?.token, 'secret');
    expect(restored?.trust.spki, trust.spki);
    await storage.clear();
    expect((await ServerTrustStore.read(url))?.opaqueKey, trust.opaqueKey);
    expect(values.containsKey('phonolite.auth.session.v1'), isFalse);
  });
  test('unsupported saved sessions are rejected without conversion', () async {
    const storage = AuthStorage();
    final valid = AuthCredentials(
      baseUrl: 'https://secure.test:3000/api',
      token: 'secret',
      username: 'listener',
      trust: trust,
    ).toJson();
    for (final invalid in [
      {...valid}..remove('profile'),
      {...valid}..remove('trust'),
      {...valid, 'profile': 'unsupported'},
      {...valid, 'baseUrl': 'http://secure.test:3000/api'},
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

class _FakeHttpClient implements HttpClient {
  final int id;
  final List<String> events;
  Future<HttpClientRequest>? pendingRequest;

  _FakeHttpClient(this.id, this.events);

  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  Duration? connectionTimeout;
  @override
  int? maxConnectionsPerHost;
  @override
  bool autoUncompress = true;
  @override
  String? userAgent;
  @override
  bool Function(X509Certificate, String, int)? badCertificateCallback;
  @override
  String Function(Uri)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    events.add('open:$id');
    if (pendingRequest != null) return pendingRequest!;
    throw const HttpException('Fake request stopped before opening a socket');
  }

  @override
  void close({bool force = false}) => events.add('close:$id:$force');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  Object? abortError;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => abortError = exception;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
