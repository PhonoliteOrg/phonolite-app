import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phonolite/updates');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'initialize'
          ? {
              'available': true,
              'feedUrl': 'https://github.com/PhonoliteOrg/phonolite-app/releases/latest/download/windows-appcast.xml',
              'currentVersion': '0.2.0.4',
            }
          : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('initialization reads compiled configuration and opens UI only on request', () async {
    final platform = WindowsAppUpdatePlatform();
    final settings = await platform.initialize(onInstall: () async {});
    expect(settings.available, isTrue);
    expect(settings.currentVersion, '0.2.0.4');
    expect(Uri.parse(settings.feedUrl).scheme, 'https');
    expect(calls.map((call) => call.method), ['initialize']);
    await platform.showUpdate();
    await platform.dispose();
    expect(calls.map((call) => call.method), ['initialize', 'showUpdate', 'dispose']);
  });

  test('native installer callback waits for the application shutdown workflow', () async {
    final closing = Completer<void>();
    final platform = WindowsAppUpdatePlatform();
    await platform.initialize(onInstall: () => closing.future);
    var replied = false;
    final callback = messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('shutdownForUpdate')),
      (_) => replied = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(replied, isFalse);
    closing.complete();
    await callback;
    expect(replied, isTrue);
    await platform.dispose();
  });
}
