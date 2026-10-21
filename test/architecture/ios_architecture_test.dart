import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/xcode_project.dart';

void main() {
  test('Xcode registers native sources once and resolves the moved build script', () {
    final project = XcodeProject(File('ios/Runner.xcodeproj/project.pbxproj'));

    for (final target in ['Runner', 'RunnerTests']) {
      final registered = project.sources(target);
      final expected = _files(
        'ios/$target',
      ).where((file) => RegExp(r'\.(?:swift|m|mm|c)$').hasMatch(file.path)).map(_path).toSet();

      expect(registered.length, registered.toSet().length, reason: '$target must not compile duplicate source entries');
      expect(registered.toSet(), expected, reason: '$target membership must match the physical native source tree');
    }

    final references = project.filePaths.values.toSet();

    for (final header in _files('ios/Runner').where((file) => file.path.endsWith('.h'))) {
      expect(references, contains(_path(header)), reason: 'Keep native headers registered at their actual paths');
    }

    expect(references, contains(_path(File('ios/Scripts/build_opus_static.sh'))));
    expect(
      project.shellScripts('Runner')['Build Opus Static'],
      contains(r'$PROJECT_DIR/Scripts/build_opus_static.sh'),
      reason: 'The active Opus build phase must invoke the registered script at its new physical path',
    );
  });

  test('native Swift follows responsibility areas and keeps entry points in Bootstrap', () {
    const areas = {'Bootstrap', 'Data', 'Application', 'Infrastructure', 'Pages', 'UI'};

    for (final file in _swiftFiles('ios/Runner')) {
      final relative = file.path.replaceAll('\\', '/').substring('ios/Runner/'.length);

      expect(relative, contains('/'), reason: '${file.path}: native implementation belongs in a responsibility area');
      expect(areas, contains(relative.split('/').first), reason: file.path);
      expect(file.uri.pathSegments.last, matches(r'^[A-Z][A-Za-z0-9]*\.swift$'), reason: file.path);
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: file.path);
    }

    for (final name in ['AppDelegate', 'SceneDelegate', 'CarPlaySceneDelegate']) {
      expect(File('ios/Runner/Bootstrap/$name.swift').existsSync(), isTrue);
    }
  });

  test('native values and presentation stay independent of channel dictionaries', () {
    for (final file in _swiftFiles('ios/Runner')) {
      final path = file.path.replaceAll('\\', '/');
      final source = file.readAsLinesSync().where((line) => !line.trimLeft().startsWith('//')).join('\n');

      if (path.contains('/Data/')) {
        expect(
          source,
          isNot(matches(RegExp(r'^import (?:Flutter|UIKit|CarPlay|MediaPlayer)\b', multiLine: true))),
          reason: path,
        );
      }

      if (path.contains('/Pages/') || path.contains('/UI/') || path.contains('/Application/')) {
        expect(source, isNot(matches(RegExp(r'^import Flutter\b', multiLine: true))), reason: path);
        expect(source, isNot(contains('[String: Any]')), reason: '$path: decode wire payloads in channel adapters');
        expect(source, isNot(contains('URLSession')), reason: '$path: inject native artwork and browsing capabilities');
      }

      if (!path.contains('/Bootstrap/')) {
        expect(source, isNot(contains('UIApplication.shared.delegate')), reason: '$path: inject the dependency');
      }

      if (path.contains('/UI/') || path.contains('/Pages/')) {
        expect(source, isNot(contains('CarPlayArtworkLoader')), reason: '$path: inject artwork loading at Bootstrap');
      }

      if (path.contains('/Infrastructure/')) {
        final declarations = source.replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), '""');

        expect(
          declarations,
          isNot(matches(r'\b(?:AppDelegate|NativeHost|CarPlaySceneDelegate|CarPlayNavigationCoordinator)\b')),
          reason: '$path: native adapters receive typed callbacks instead of concrete host/presentation owners',
        );
      }
    }
  });
}

Iterable<File> _files(String directory) => Directory(directory).listSync(recursive: true).whereType<File>();

Iterable<File> _swiftFiles(String directory) => _files(directory).where((file) => file.path.endsWith('.swift'));

String _path(FileSystemEntity entity) => entity.absolute.path.replaceAll('\\', '/');
