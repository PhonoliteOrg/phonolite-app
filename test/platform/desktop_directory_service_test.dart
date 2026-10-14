import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/platform/desktop_directory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('phonolite/directories');
  const service = DesktopDirectoryService();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'first use opens the exact storage folder, including spaces and Unicode',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'phonolite-folder-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}${Platform.pathSeparator}Music é');
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(await folder.exists(), isTrue);
        received = call;
        return null;
      });

      await service.openDirectory(folder.path);

      expect(received?.method, 'openDirectory');
      expect(received?.arguments, folder.absolute.path);
    },
  );

  test('file manager failures reach the caller', () async {
    final root = await Directory.systemTemp.createTemp(
      'phonolite-folder-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'open_failed');
    });

    await expectLater(
      service.openDirectory(root.path),
      throwsA(isA<PlatformException>()),
    );
  });
}
