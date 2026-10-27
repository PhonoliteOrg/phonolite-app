import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:phonolite_app/data/configuration/app/desktop_window_configuration.dart';
import 'package:phonolite_app/infrastructure/platform/app/desktop_lifecycle_platform.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final view = binding.platformDispatcher.implicitView!;
  const windowChannel = MethodChannel('window_manager');
  const constraintsChannel = MethodChannel('phonolite/window');
  const trayChannel = MethodChannel('tray_manager');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NativeDesktopLifecyclePlatform platform;
  late List<MethodCall> windowCalls;
  late List<MethodCall> trayCalls;
  late List<MethodCall> constraintsCalls;
  late int closes;
  late int quits;
  late Size windowSize;

  setUp(() async {
    windowCalls = [];
    trayCalls = [];
    constraintsCalls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    closes = 0;
    quits = 0;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(1280, 720);
    windowSize = const Size(1296, 759);
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call);

      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': windowSize.width, 'height': windowSize.height};
      }

      return call.method == 'isMinimized' ? true : null;
    });
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      trayCalls.add(call);

      return null;
    });
    messenger.setMockMethodCallHandler(constraintsChannel, (call) async {
      constraintsCalls.add(call);

      return null;
    });
    platform = NativeDesktopLifecyclePlatform();
    await platform.initialize(onClose: () async => closes++, onQuit: () async => quits++);
  });

  tearDown(() async {
    await platform.dispose();
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
    messenger.setMockMethodCallHandler(constraintsChannel, null);
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
  });

  test('minimum desktop size includes decorations without resizing a larger window', () {
    expect(
      windowCalls.map((call) => call.method),
      containsAllInOrder(['ensureInitialized', 'getBounds', 'setMinimumSize', 'setPreventClose']),
    );
    final minimum = windowCalls.singleWhere((call) => call.method == 'setMinimumSize').arguments as Map;
    expect(minimum['width'], DesktopWindowConfiguration.minimumWidth + 16);
    expect(minimum['height'], DesktopWindowConfiguration.minimumHeight + 39);
    expect(windowCalls.where((call) => call.method == 'setBounds'), isEmpty);
    expect(constraintsCalls, isEmpty);
  });

  test('Linux delegates the content minimum to GTK without setting decorated frame hints', () async {
    await platform.dispose();
    windowCalls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await platform.initialize(onClose: () async => closes++, onQuit: () async => quits++);

    expect(constraintsCalls, hasLength(1));
    expect(constraintsCalls.single.method, 'setMinimumContentSize');
    expect(constraintsCalls.single.arguments, {
      'width': DesktopWindowConfiguration.minimumWidth,
      'height': DesktopWindowConfiguration.minimumHeight,
    });
    expect(windowCalls.map((call) => call.method), ['ensureInitialized', 'setPreventClose']);
  });

  for (final contentSize in [const Size(500, 300), const Size(500, 720), const Size(1280, 300)]) {
    test('undersized desktop content $contentSize is clamped without shrinking its other dimension', () async {
      await platform.dispose();
      windowCalls.clear();
      view.devicePixelRatio = 1.5;
      view.physicalSize = contentSize * 1.5;
      windowSize = Size(contentSize.width + 16, contentSize.height + 39);

      await platform.initialize(onClose: () async => closes++, onQuit: () async => quits++);

      final minimum = windowCalls.singleWhere((call) => call.method == 'setMinimumSize').arguments as Map;
      expect(minimum['width'], 616);
      expect(minimum['height'], 399);
      final resized = windowCalls.singleWhere((call) => call.method == 'setBounds').arguments as Map;
      expect(resized['width'], contentSize.width < 600 ? 616 : windowSize.width);
      expect(resized['height'], contentSize.height < 360 ? 399 : windowSize.height);
      expect(resized, isNot(contains('x')));
      expect(resized, isNot(contains('y')));
    });
  }

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
