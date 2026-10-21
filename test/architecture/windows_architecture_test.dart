import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  test('Windows runner explicitly registers every handwritten native component once', () {
    final build = readProjectFile('windows/runner/CMakeLists.txt');
    final executable = RegExp(r'add_executable\([\s\S]*?\n\)').firstMatch(build)![0]!;
    final references = RegExp(r'"([^"\n]+\.(?:cpp|cc|h))"')
        .allMatches(executable)
        .map((match) => match[1]!)
        .where((path) => !path.contains(r'${FLUTTER_MANAGED_DIR}'))
        .toList();
    final expected = _nativeFiles()
        .where((file) => !file.path.endsWith('resource.h'))
        .map((file) => file.path.replaceAll('\\', '/').substring('windows/runner/'.length))
        .toSet();

    expect(references.length, references.toSet().length, reason: 'Do not compile or register a component twice');
    expect(references.toSet(), expected);
    expect(executable, contains(r'"${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"'));
    expect(executable, contains('"Runner.rc"'));
    expect(executable, contains('"runner.exe.manifest"'));
  });

  test('Windows values, frame and channel transport keep their responsibility boundaries', () {
    const areas = {'bootstrap', 'data', 'infrastructure', 'ui'};

    for (final file in _nativeFiles().where((file) => !file.path.endsWith('resource.h'))) {
      final path = file.path.replaceAll('\\', '/');
      final relative = path.substring('windows/runner/'.length);
      final source = file.readAsStringSync();

      expect(file.uri.pathSegments.last, matches(r'^[a-z][a-z0-9_]*\.(?:cpp|h)$'), reason: path);
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: path);

      if (relative == 'main.cpp') {
        continue;
      }

      expect(areas, contains(relative.split('/').first), reason: path);

      if (relative.startsWith('data/')) {
        expect(source, isNot(contains('#include <windows.h>')), reason: path);
        expect(source, isNot(contains('#include <flutter/')), reason: path);
        expect(source, isNot(contains('ShellExecute')), reason: path);
      }

      if (relative.startsWith('ui/')) {
        expect(source, isNot(contains('MethodChannel')), reason: path);
        expect(source, isNot(contains('ShellExecute')), reason: path);
        expect(source, isNot(contains('runner/bootstrap/')), reason: path);
      }

      if (relative.startsWith('infrastructure/')) {
        expect(source, isNot(contains('runner/bootstrap/')), reason: path);
        expect(source, isNot(contains('FlutterWindow')), reason: path);
      }

      expect(source, isNot(matches(RegExp(r'#include\s+"(?:\.\./|[A-Za-z]:)'))), reason: path);
    }
  });

  test('Windows host preserves startup order, handler teardown and directory replies', () {
    final host = readProjectFile('windows/runner/bootstrap/flutter_window.cpp');
    final order = [
      'Win32Window::on_create()',
      'RegisterPlugins(',
      'set_child_content(',
      'directory_channel_->attach(',
      'SetNextFrameCallback(',
      'ForceRedraw()',
    ].map(host.indexOf).toList();

    expect(order, everyElement(greaterThanOrEqualTo(0)));
    expect(order, orderedEquals([...order]..sort()));
    expect(host.indexOf('directory_channel_->detach()'), lessThan(host.indexOf('flutter_controller_.reset()')));

    final adapter = readProjectFile('windows/runner/infrastructure/flutter/directories_channel_adapter.cpp');
    final launcher = readProjectFile('windows/runner/infrastructure/shell/directory_launcher.cpp');

    expectContainsAll(adapter, const [
      '"phonolite/directories"',
      '"openDirectory"',
      '"invalid_path", "A folder path is required."',
      '"invalid_path", "The folder path is not valid UTF-8."',
      '"open_failed", "Could not open the folder."',
      'result->NotImplemented()',
      'result->Success()',
      'SetMethodCallHandler(nullptr)',
    ]);
    expectContainsAll(launcher, const [
      'ShellExecuteW(owner_window_, L"open", folder_path.c_str(), nullptr, nullptr, SW_SHOWNORMAL)',
    ]);
  });
}

Iterable<File> _nativeFiles() => Directory(
  'windows/runner',
).listSync(recursive: true).whereType<File>().where((file) => RegExp(r'\.(?:cpp|h)$').hasMatch(file.path));
