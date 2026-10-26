import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const trayChannel = MethodChannel('tray_manager');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NativeDesktopLifecyclePlatform platform;
  late List<MethodCall> windowCalls;
  late List<MethodCall> trayCalls;
  late int closes;
  late int quits;

  setUp(() async {
    windowCalls = [];
    trayCalls = [];
    closes = 0;
    quits = 0;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call);

      return call.method == 'isMinimized' ? true : null;
    });
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      trayCalls.add(call);

      return null;
    });
    platform = NativeDesktopLifecyclePlatform();
    await platform.initialize(onClose: () async => closes++, onQuit: () async => quits++);
  });

  tearDown(() async {
    await platform.dispose();
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
  });

  test('tray has Show and Quit; showing restores a minimized window', () async {
    await platform.setBackgroundEnabled(true);
    final menu = trayCalls.singleWhere((call) => call.method == 'setContextMenu');
    final items = ((menu.arguments as Map)['menu'] as Map)['items'] as List;
    expect(items.map((item) => (item as Map)['label']), containsAll(['Show Phonolite', 'Quit Phonolite']));
    await platform.show();
    expect(windowCalls.map((call) => call.method), containsAllInOrder(['isMinimized', 'restore', 'show', 'focus']));
  });

  test('turning background mode off restores the window before removing its tray', () async {
    await platform.setBackgroundEnabled(true);
    windowCalls.clear();
    await platform.setBackgroundEnabled(false);
    expect(windowCalls.map((call) => call.method), ['isMinimized', 'restore', 'show', 'focus']);
    expect(trayCalls.last.method, 'destroy');
  });

  test('native close and tray Quit dispatch distinct actions', () async {
    platform.onWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
    expect(quits, 0);
    platform.onTrayMenuItemClick(MenuItem(key: 'quit', label: 'Quit Phonolite'));
    await Future<void>.delayed(Duration.zero);
    expect(quits, 1);
    await platform.quit();
    expect(windowCalls.last.method, 'destroy');
  });
}
