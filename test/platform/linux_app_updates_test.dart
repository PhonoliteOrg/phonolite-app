import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:phonolite_app/application/controllers/settings/app_updates_controller.dart';
import 'package:phonolite_app/data/models/updates/app_update_progress.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_backend.dart';
import 'package:phonolite_app/infrastructure/platform/app/linux_app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/linux_update_process.dart';
import 'package:phonolite_app/infrastructure/updates/linux_update_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux assembly shares one discovery and installation owner', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final backend = AppUpdateBackend.current();
      expect(backend.platform, isA<LinuxAppUpdatePlatform>());
      expect(identical(backend.platform, backend.feed), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('unmanaged installations expose the native disabled reason', () async {
    final process = _Process()..managed = false;
    final platform = LinuxAppUpdatePlatform(process: process);
    final configuration = await platform.initialize(onInstall: () async {});
    expect(configuration.available, isFalse);
    expect(configuration.disabledReason, 'Externally managed installation.');
    expect(process.commands, [
      ['--describe'],
    ]);
    await platform.dispose();
  });

  test('an interrupted receipt remains visible until an explicit recovery check', () async {
    final process = _Process()..receipt = {'state': 'interrupted'};
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    final controller = AppUpdatesController(platform: platform, feed: platform, isSupported: () => true);
    try {
      await controller.initialize(onPrepare: () async {}, onInstall: () async {});
      expect(platform.progress.value.phase, AppUpdatePhase.recoveryRequired);
      expect(process.commands, [
        ['--describe'],
      ]);
      expect(controller.canCheckForUpdates, isTrue);
      expect(controller.latestRelease, isNull);
      await controller.checkForUpdates();
      expect(platform.progress.value.phase, AppUpdatePhase.idle);
      expect(controller.latestRelease!.version, '0.5.0');
    } finally {
      await controller.shutdown();
      controller.dispose();
    }
  });

  test('only verified manifest output can become an available release', () async {
    final process = _Process();
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    final configuration = await platform.initialize(onInstall: () async {});
    process.invalid = true;
    await expectLater(platform.latest(configuration), throwsStateError);
    expect(process.coordinates, 0);
    process.invalid = false;
    final latest = await platform.latest(configuration);
    expect(latest!.version, '0.5.0');
    expect(process.commands.last.first, '--select');
    await platform.dispose();
  });

  test('authorization cancellation keeps shutdown uncalled and permits retry', () async {
    final process = _Process()..response = 'failed';
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    var prepared = 0;
    var quit = 0;
    platform.setPreparationCallback(() async => prepared++);
    final configuration = await platform.initialize(onInstall: () async => quit++);
    await platform.latest(configuration);
    await expectLater(platform.showUpdate(), throwsStateError);
    expect(prepared, 0);
    expect(quit, 0);
    expect(platform.progress.value.phase, AppUpdatePhase.failed);
    await expectLater(platform.showUpdate(), throwsStateError);
    expect(process.coordinates, 2);
    await platform.dispose();
    await process.cleanup();
  });

  test('cleanup must succeed before prepared is sent and quit runs', () async {
    final process = _Process();
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    var quit = 0;
    platform.setPreparationCallback(() async => throw StateError('Storage flush failed'));
    final configuration = await platform.initialize(onInstall: () async => quit++);
    await platform.latest(configuration);
    await expectLater(platform.showUpdate(), throwsStateError);
    expect(process.child!.input.join(), 'abort\n');
    expect(quit, 0);
    expect(platform.progress.value.phase, AppUpdatePhase.restartRequired);
    await platform.dispose();
    await process.cleanup();
  });

  test('the coordinator receives preparation before quit, and survives disposal', () async {
    final process = _Process();
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    var prepared = false;
    platform.setPreparationCallback(() async => prepared = true);
    final configuration = await platform.initialize(
      onInstall: () async {
        expect(prepared, isTrue);
        expect(process.child!.input.join(), 'prepared\n');
        await platform.dispose();
      },
    );
    await platform.latest(configuration);
    await expectLater(platform.showUpdate(), throwsStateError);
    expect(process.child!.killed, isFalse);
    expect(await Directory(process.stages.last).exists(), isTrue);
    await process.cleanup();
  });

  test('cancellation during final verification cannot request authorization', () async {
    final process = _Process();
    final platform = LinuxAppUpdatePlatform(process: process, transport: _transport());
    platform.setPreparationCallback(() async {});
    final configuration = await platform.initialize(onInstall: () async {});
    await platform.latest(configuration);
    final verifying = Completer<void>();
    process.verification = verifying;
    platform.progress.addListener(() {
      if (platform.progress.value.phase == AppUpdatePhase.verifying) platform.cancelDownload();
    });
    final install = platform.showUpdate();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verifying.complete();
    await install;
    expect(process.coordinates, 0);
    expect(platform.progress.value.phase, AppUpdatePhase.idle);
    await platform.dispose();
  });

  test('downloads reject changed bytes and remove incomplete files', () async {
    final directory = await Directory.systemTemp.createTemp('phonolite-download-test-');
    final path = File('${directory.path}/candidate');
    final transport = LinuxUpdateTransport(createClient: () => MockClient((_) async => http.Response('altered', 200)));
    try {
      await expectLater(
        transport.download(
          Uri.parse('https://example.com/pkg'),
          path,
          length: 7,
          digest: sha256.convert(utf8.encode('correct')).toString(),
          onProgress: (_) {},
        ),
        throwsFormatException,
      );
      expect(await path.exists(), isFalse);
    } finally {
      transport.cancel();
      await directory.delete(recursive: true);
    }
  });

  test('bounded HTTPS transport rejects insecure redirects and oversized metadata', () async {
    final transport = LinuxUpdateTransport(
      createClient: () =>
          MockClient((_) async => http.Response('', 302, headers: {'location': 'http://example.com/unsafe'})),
    );
    await expectLater(transport.metadata(Uri.parse('https://example.com/feed')), throwsFormatException);
    final oversized = LinuxUpdateTransport(createClient: () => MockClient((_) async => http.Response('12345', 200)));
    await expectLater(oversized.metadata(Uri.parse('https://example.com/feed'), maximum: 4), throwsFormatException);
  });

  test('cancellation retires the active generation', () async {
    final body = StreamController<List<int>>();
    final transport = LinuxUpdateTransport(
      createClient: () => MockClient.streaming((_, _) async => http.StreamedResponse(body.stream, 200)),
    );
    final reading = transport.metadata(Uri.parse('https://example.com/feed'));
    final expected = expectLater(reading, throwsA(isA<UpdateDownloadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    transport.cancel();
    body.add([1]);
    await body.close();
    await expected;
  });
}

LinuxUpdateTransport _transport() => LinuxUpdateTransport(
  createClient: () =>
      MockClient((request) async => http.Response(request.url.path == '/pkg.deb' ? 'package bytes' : '{}', 200)),
);

class _Process extends LinuxUpdateProcess {
  bool managed = true;
  Map<String, dynamic>? receipt;
  bool invalid = false;
  Completer<void>? verification;
  String response = 'ready';
  int coordinates = 0;
  final commands = <List<String>>[];
  final stages = <String>[];
  _Child? child;

  @override
  Future<Object?> command(List<String> arguments) async {
    commands.add(arguments);
    if (arguments.first == '--describe') {
      return {
        'available': managed,
        'receipt': receipt,
        'reason': managed ? null : 'Externally managed installation.',
        'currentVersion': '0.4.0-1',
        'feedUrl': 'https://example.com/manifest',
        'signatureUrl': 'https://example.com/signature',
      };
    }
    if (invalid) throw StateError('Invalid manifest signature.');
    await verification?.future;
    return {
      'version': '0.5.0',
      'package_version': '0.5.0-1',
      'target': 'ubuntu-26.04-amd64',
      'format': 'deb',
      'architecture': 'amd64',
      'url': 'https://example.com/pkg.deb',
      'sha256': sha256.convert(utf8.encode('package bytes')).toString(),
      'length': 13,
    };
  }

  @override
  Future<Process> coordinate(String directory) async {
    coordinates++;
    stages.add(directory);
    final request = jsonDecode(await File('$directory/request.json').readAsString()) as Map<String, dynamic>;
    child = _Child(response, request['correlation'] as String);
    return child!;
  }

  Future<void> cleanup() async {
    for (final path in stages) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}

class _Child implements Process {
  final input = <String>[];
  final String response;
  final String correlation;
  bool killed = false;
  late final IOSink _stdin;

  _Child(this.response, this.correlation) {
    final bytes = StreamController<List<int>>();
    bytes.stream.transform(utf8.decoder).listen(input.add);
    _stdin = IOSink(bytes.sink);
  }

  @override
  int get pid => 123;
  @override
  IOSink get stdin => _stdin;
  @override
  Stream<List<int>> get stdout => Stream.value(
    utf8.encode(
      '${jsonEncode({'event': response, 'correlation': correlation, 'message': 'Authorization cancelled.'})}\n',
    ),
  );
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => Future.value(0);
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => killed = true;
}
