import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';
import '../support/xcode_project.dart';

const _runner = 'macos/Runner';
const _native = '$_runner/Infrastructure/Audio/Native';

void main() {
  test('macOS Xcode membership resolves each physical source and header once', () {
    final project = XcodeProject(File('macos/Runner.xcodeproj/project.pbxproj'));

    for (final target in ['Runner', 'RunnerTests']) {
      final expected = _files(
        'macos/$target',
      ).where((file) => RegExp(r'\.(?:swift|c|m|mm)$').hasMatch(file.path)).map(_path).toSet();

      if (target == 'Runner') {
        expected.add(_path(File('macos/Flutter/GeneratedPluginRegistrant.swift')));
      }

      final registered = project.sources(target);

      expect(registered.length, registered.toSet().length, reason: '$target must not compile a source twice');
      expect(registered.toSet(), expected, reason: '$target source membership must follow the physical folders');
    }

    final references = project.filePaths.values.toSet();

    for (final header in _files(_runner).where((file) => file.path.endsWith('.h'))) {
      expect(references, contains(_path(header)), reason: header.path);
    }

    expect(references, contains(_path(File('macos/Scripts/build_opus_static.sh'))));
    expect(
      project.shellScripts('Runner')['Build Opus Static'],
      contains(r'/bin/bash "$PROJECT_DIR/Scripts/build_opus_static.sh"'),
    );
  });

  test('macOS native owners follow responsibility areas without reaching through the host', () {
    for (final file in _files(_runner).where((file) => file.path.endsWith('.swift'))) {
      final path = file.path.replaceAll('\\', '/');
      final relative = path.substring('$_runner/'.length);
      final source = file.readAsStringSync();

      expect(relative.split('/').first, isIn(['Bootstrap', 'Infrastructure']), reason: path);
      expect(file.uri.pathSegments.last, matches(r'^[A-Z][A-Za-z0-9]*\.swift$'), reason: path);
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: path);

      if (relative.startsWith('Infrastructure/')) {
        expect(source, isNot(contains('NSApplication.shared.delegate')), reason: path);
        expect(source, isNot(matches(r'\b(?:AppDelegate|MainFlutterWindow|FlutterEngineBinding)\b')), reason: path);
      }

      if (relative.startsWith('Infrastructure/Shell/')) {
        expect(source, isNot(contains('FlutterMacOS')), reason: path);
      }

      if (relative.startsWith('Bootstrap/')) {
        expect(source, isNot(contains('FlutterError(')), reason: '$path: channel parsing belongs in its adapter');
        expect(source, isNot(contains('NSWorkspace.shared')), reason: '$path: inject the platform capability');
      }
    }
  });

  test('macOS preserves nib identities and the Flutter startup and teardown order', () {
    final window = readProjectFile('$_runner/Bootstrap/MainFlutterWindow.swift');
    final startup = [
      'FlutterViewController()',
      'let windowFrame = frame',
      'contentViewController = flutterViewController',
      'setFrame(windowFrame, display: true)',
      'RegisterGeneratedPlugins(registry: flutterViewController)',
      'FlutterEngineBinding(messenger: flutterViewController.engine.binaryMessenger)',
      'binding.attach()',
      'engineBinding = binding',
      'super.awakeFromNib()',
    ].map(window.indexOf).toList();

    expect(startup, everyElement(greaterThanOrEqualTo(0)));
    expect(startup, orderedEquals([...startup]..sort()));
    expect(window, matches(r'deinit\s*\{\s*engineBinding\?\.detach\(\)'));
    expect(window.indexOf('engineBinding?.detach()', window.indexOf('awakeFromNib()')), lessThan(startup.first));

    final menu = readProjectFile('$_runner/Base.lproj/MainMenu.xib');
    expectContainsAll(menu, const [
      'customClass="AppDelegate"',
      'customClass="MainFlutterWindow"',
      'customModule="Runner"',
      'property="applicationMenu"',
      'property="mainFlutterWindow"',
    ]);

    final delegate = readProjectFile('$_runner/Bootstrap/AppDelegate.swift');
    expectContainsAll(delegate, const [
      '@main',
      'applicationShouldTerminateAfterLastWindowClosed',
      'applicationSupportsSecureRestorableState',
    ]);
  });

  test('macOS directory transport keeps wire replies separate from the system opener', () {
    final adapter = readProjectFile('$_runner/Infrastructure/Flutter/DirectoriesChannelAdapter.swift');

    expectContainsAll(adapter, const [
      '"phonolite/directories"',
      '"openDirectory"',
      'call.arguments as? String, !path.isEmpty',
      'URL(fileURLWithPath: path, isDirectory: true)',
      'code: "invalid_path", message: "A folder path is required.", details: nil',
      'code: "open_failed", message: "Could not open the folder.", details: nil',
      'result(FlutterMethodNotImplemented)',
      'result(nil)',
      'guard !isAttached',
      'setMethodCallHandler(nil)',
    ]);
    expect(adapter, isNot(contains('NSWorkspace')));

    final launcher = readProjectFile('$_runner/Infrastructure/Shell/DirectoryLauncher.swift');
    expectContainsAll(launcher, const [r'NSWorkspace.shared.open($0)', 'return openURL(directory)']);
    expect(launcher, isNot(contains('Flutter')));
  });

  test('macOS exported audio facade retains every Dart symbol with opaque resource boundaries', () {
    final bindings = readProjectFile('lib/infrastructure/platform/audio/apple/core_audio_bindings.dart');
    final expected = RegExp(r"'(phonolite_audio_\w+)'").allMatches(bindings).map((match) => match[1]!).toSet();
    final header = readProjectFile('$_native/phonolite_audio.h');
    final facade = readProjectFile('$_native/phonolite_audio.c');
    final exported = RegExp(
      r'PHONOLITE_EXPORT\s+[^;{]+?\b(phonolite_audio_\w+)\(',
    ).allMatches(facade).map((match) => match[1]!).toList();

    expect(expected, hasLength(12));
    expect(exported, unorderedEquals(expected));
    expect(header, contains('extern "C"'));

    for (final symbol in expected) {
      expect(header, contains('$symbol('));
    }

    expect(header, isNot(contains('AudioQueueRef')));
    expect(header, isNot(contains('pthread_mutex_t')));
    expect(facade, isNot(contains('AudioQueueStart')));
    expect(facade, isNot(contains('AudioObjectGetPropertyData')));

    for (final file in _files(_native).where((file) => file.path.endsWith('.c'))) {
      expect(file.readAsStringSync(), isNot(matches(r'#include\s+"[^"\n]+\.c"')), reason: file.path);
    }
  });

  test('macOS queue generation and synchronous disposal preserve the callback context lifetime', () {
    final queue = readProjectFile('$_native/audio_queue_player.c');
    final close = queue.substring(
      queue.indexOf('void audio_queue_player_close('),
      queue.indexOf('int32_t audio_queue_player_write('),
    );

    expect(close.indexOf('AudioQueueDispose(player->queue, true)'), lessThan(close.indexOf('free(player)')));
    expectContainsAll(queue, const [
      'max_in_flight = 5',
      'queue_full = -3',
      'entry->generation == player->generation',
      'atomic_exchange(&player->completed_samples, 0)',
      'atomic_store(&player->in_flight, 0)',
      'atomic_store(&player->completed_samples, 0)',
      'AudioQueueReset(player->queue)',
      'memcpy(buffer->mAudioData, samples, byte_size)',
    ]);
  });
}

Iterable<File> _files(String directory) => Directory(directory).listSync(recursive: true).whereType<File>();

String _path(FileSystemEntity entity) => entity.absolute.path.replaceAll('\\', '/');
