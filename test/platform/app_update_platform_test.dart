import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/data/models/updates/app_update_progress.dart';
import 'package:phonolite_app/data/models/updates/windows_update_asset.dart';
import 'package:phonolite_app/data/storage/updates/windows_update_staging.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_backend.dart';
import 'package:phonolite_app/infrastructure/platform/app/windows_app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_transport.dart';
import 'package:phonolite_app/infrastructure/updates/windows_update_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phonolite/updates');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final events = <String>[];
  final payload = utf8.encode('Signed fixture only. Never execute this file.');
  late String publicKey;
  late String signature;
  late Directory root;
  late WindowsAppUpdatePlatform platform;
  var nativeFails = false;
  var stageFails = false;
  File? stagedCandidate;

  setUpAll(() async {
    final algorithm = Ed25519();
    final key = await algorithm.newKeyPairFromSeed(List.generate(32, (index) => index));
    publicKey = base64.encode((await key.extractPublicKey()).bytes);
    signature = base64.encode((await algorithm.sign(payload, keyPair: key)).bytes);
  });

  setUp(() async {
    calls.clear();
    events.clear();
    nativeFails = false;
    stageFails = false;
    stagedCandidate = null;
    root = await Directory.systemTemp.createTemp('phonolite-update-test-');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return {
          'available': true,
          'feedUrl': 'https://example.com/windows-appcast.xml',
          'currentVersion': '0.2.0.4',
          'publicKey': publicKey,
        };
      }
      if (call.method == 'stageUpdate') {
        if (stageFails) throw PlatformException(code: 'update_install_failed', message: 'Installer version mismatch');
        stagedCandidate = File((call.arguments as Map)['path'] as String);
        expect((call.arguments as Map)['version'], '0.3.0.1');
      }
      if (call.method == 'installUpdate') {
        events.add('install');
        expect(await stagedCandidate!.readAsBytes(), payload);
        if (nativeFails) throw PlatformException(code: 'update_install_failed');
      }
      return null;
    });
  });

  tearDown(() async {
    await platform.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<void> initialize({
    List<int>? download,
    String? proof,
    int? length,
    AppUpdateTransport? transport,
    WindowsUpdateVerifier verifier = const WindowsUpdateVerifier(),
    Future<void> Function()? prepare,
    Future<void> Function()? quit,
  }) async {
    final feed = HttpAppUpdateFeed(
      createClient: () => MockClient(
        (_) async => http.Response('''
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><sparkle:version>0.3.0.1</sparkle:version>
<enclosure url="https://example.com/update.exe" length="${length ?? payload.length}"
sparkle:os="windows-x64" sparkle:edSignature="${proof ?? signature}"/>
</item></channel></rss>''', 200),
      ),
    );
    platform = WindowsAppUpdatePlatform(
      feed: feed,
      staging: WindowsUpdateStaging(root: root),
      transport:
          transport ??
          AppUpdateTransport(
            createClient: () => MockClient((_) async => http.Response.bytes(download ?? payload, 200)),
          ),
      verifier: verifier,
    );
    platform.setPreparationCallback(prepare ?? () async => events.add('prepare'));
    final configuration = await platform.initialize(onInstall: quit ?? () async => events.add('quit'));
    expect(configuration.publicKey, publicKey);
    await platform.latest(configuration);
  }

  test('Windows assembly uses one owner for discovery and installation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final backend = AppUpdateBackend.current();
      expect(backend.platform, isA<WindowsAppUpdatePlatform>());
      expect(identical(backend.platform, backend.feed), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    await initialize();
  });

  test('downloads and verifies inside the app before preparing, installing and quitting', () async {
    await initialize();
    expect(calls.map((call) => call.method), ['initialize']);
    final phases = <AppUpdatePhase>[];
    platform.progress.addListener(() => phases.add(platform.progress.value.phase));
    await platform.showUpdate();
    expect(events, ['prepare', 'install', 'quit']);
    expect(calls.map((call) => call.method), ['initialize', 'stageUpdate', 'installUpdate']);
    expect(
      phases,
      containsAllInOrder([
        AppUpdatePhase.downloading,
        AppUpdatePhase.verifying,
        AppUpdatePhase.preparing,
        AppUpdatePhase.installing,
      ]),
    );
    // The installer owns the staged file after handoff; disposal cannot remove it.
    await platform.dispose();
    expect(await root.list().length, 1);
    await expectLater(platform.showUpdate(), throwsStateError);
  });

  test('changed bytes never prepare, install or quit and remove the stage', () async {
    await initialize(download: List.filled(payload.length, 0));
    await expectLater(platform.showUpdate(), throwsFormatException);
    expect(events, isEmpty);
    expect(platform.progress.value.phase, AppUpdatePhase.failed);
    expect(await root.list().length, 0);
    expect(calls.map((call) => call.method), ['initialize', 'stageUpdate', 'releaseUpdate']);
  });

  test('an embedded installer version mismatch never prepares or quits the app', () async {
    await initialize();
    stageFails = true;
    await expectLater(platform.showUpdate(), throwsA(isA<PlatformException>()));
    expect(events, isEmpty);
    expect(platform.progress.value.phase, AppUpdatePhase.failed);
    expect(await root.list().length, 0);
  });

  test('cancelling an active download removes partial files without staging or quitting', () async {
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: () => listening.complete());
    await initialize(
      transport: AppUpdateTransport(
        createClient: () => MockClient.streaming((_, _) async => http.StreamedResponse(body.stream, 200)),
      ),
    );
    final updating = platform.showUpdate();
    await listening.future;
    platform.cancelDownload();
    body.add(payload);
    await body.close();
    await updating;
    expect(events, isEmpty);
    expect(calls.map((call) => call.method), ['initialize']);
    expect(platform.progress.value.phase, AppUpdatePhase.idle);
    expect(await root.list().length, 0);
  });

  test('an update signed by another key is rejected', () async {
    final otherKey = await Ed25519().newKeyPairFromSeed(List.filled(32, 99));
    final proof = base64.encode((await Ed25519().sign(payload, keyPair: otherKey)).bytes);
    await initialize(proof: proof);
    await expectLater(platform.showUpdate(), throwsFormatException);
    expect(events, isEmpty);
    expect(await root.list().length, 0);
  });

  test('truncated and oversized downloads cannot reach verification or installation', () async {
    await initialize(length: payload.length + 1);
    await expectLater(platform.showUpdate(), throwsFormatException);
    expect(events, isEmpty);
    expect(await root.list().length, 0);
  });

  test('cancelling signature verification prevents preparation and allows retry', () async {
    final verifier = _PausedVerifier();
    await initialize(verifier: verifier);
    final updating = platform.showUpdate();
    await verifier.started.future;
    platform.cancelDownload();
    verifier.resume.complete();
    await updating;
    expect(events, isEmpty);
    expect(platform.progress.value.phase, AppUpdatePhase.idle);
    expect(await root.list().length, 0);
    await platform.showUpdate();
    expect(events, ['prepare', 'install', 'quit']);
  });

  test('closing during verification waits for cleanup and never launches an installer', () async {
    final verifier = _PausedVerifier();
    await initialize(verifier: verifier);
    final updating = platform.showUpdate();
    await verifier.started.future;
    final closing = platform.dispose();
    verifier.resume.complete();
    await Future.wait([updating, closing]);
    expect(events, isEmpty);
    expect(await root.list().length, 0);
  });

  test('duplicate clicks do not start a second download or installation', () async {
    final verifier = _PausedVerifier();
    await initialize(verifier: verifier);
    final updating = platform.showUpdate();
    await verifier.started.future;
    await platform.showUpdate();
    verifier.resume.complete();
    await updating;
    expect(events, ['prepare', 'install', 'quit']);
  });

  test('state-saving failure keeps the installer unstarted and requires a restart', () async {
    await initialize(prepare: () async => throw StateError('Could not save settings'));
    await expectLater(platform.showUpdate(), throwsStateError);
    expect(events, isEmpty);
    expect(platform.progress.value.phase, AppUpdatePhase.restartRequired);
    expect(await root.list().length, 0);
  });

  test('process creation failure never quits and reports the error in the app', () async {
    await initialize();
    nativeFails = true;
    await expectLater(platform.showUpdate(), throwsA(isA<PlatformException>()));
    expect(events, ['prepare', 'install']);
    expect(platform.progress.value.phase, AppUpdatePhase.restartRequired);
    expect(await root.list().length, 0);
  });

  test('quit can dispose the backend without deadlocking or deleting the installer', () async {
    await initialize(
      quit: () async {
        events.add('quit');
        await platform.dispose();
      },
    );
    await platform.showUpdate();
    expect(events, ['prepare', 'install', 'quit']);
    expect(await root.list().length, 1);
  });
}

class _PausedVerifier extends WindowsUpdateVerifier {
  final started = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<void> verify(File candidate, WindowsUpdateAsset asset, String publicKey) async {
    if (!started.isCompleted) started.complete();
    await resume.future;
    await super.verify(candidate, asset, publicKey);
  }
}
