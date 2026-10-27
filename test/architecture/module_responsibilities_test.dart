import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concrete source libraries have no import or export cycles', () {
    final files = {for (final file in _dartFiles('lib')) _path(file): file};
    final paths = files.keys.toSet();
    final directives = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
    final dependencies = <String, Set<String>>{};

    for (final entry in files.entries) {
      dependencies[entry.key] = {
        for (final directive in directives.allMatches(entry.value.readAsStringSync()))
          if (directive[1]!.startsWith('package:phonolite_app/') || !directive[1]!.contains(':'))
            _path(_resolve(entry.value, directive[1]!)),
      }.intersection(paths);
    }

    final visited = <String>{};
    final pending = <String>[];
    final cycles = <String>[];

    void visit(String library) {
      final cycleStart = pending.indexOf(library);
      if (cycleStart >= 0) {
        cycles.add([...pending.skip(cycleStart), library].join(' -> '));

        return;
      }

      if (!visited.add(library)) {
        return;
      }

      pending.add(library);

      for (final dependency in dependencies[library]!) {
        visit(dependency);
      }

      pending.removeLast();
    }

    for (final library in files.keys) {
      visit(library);
    }

    expect(cycles, isEmpty, reason: 'Inject narrow capabilities instead of importing a consuming facade.');
  });

  test('module documentation stays outside the lib source tree', () {
    final readmes = Directory('lib').listSync(recursive: true).whereType<File>().where((file) {
      final filename = file.uri.pathSegments.last;

      return RegExp(r'^readme(?:\..*)?$', caseSensitive: false).hasMatch(filename);
    });

    expect(readmes.map((file) => file.path), isEmpty);
  });

  test('lib files remain within the current readability size boundary', () {
    final oversized = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final count = file.readAsLinesSync().length;
      if (count > 1000) oversized.add('${file.path}: $count lines');
    }
    expect(oversized, isEmpty, reason: 'Split by responsibility before extending these files.');
  });

  test('every lib source belongs to a documented responsibility area', () {
    final documented = RegExp(
      r'^\| `lib/([^/`]+)/` \|',
      multiLine: true,
    ).allMatches(File('docs/expected-architecture.md').readAsStringSync()).map((match) => match[1]!).toList();
    final sources = _dartFiles('lib').map((file) => file.path.replaceAll('\\', '/')).toSet();
    final areas = sources
        .map((path) => path.substring('lib/'.length))
        .where((path) => path.contains('/'))
        .map((path) => path.split('/').first)
        .toSet();
    expect(documented.length, documented.toSet().length);
    expect(documented.toSet(), areas);
    expect(
      sources.where((path) => !path.substring('lib/'.length).contains('/')).toSet(),
      {'lib/main.dart'},
      reason: 'Only the thin entry point belongs at the source root.',
    );
  });

  test('part-based components contain only their entry point and own parts', () {
    final partDirective = RegExp(r'''^part\s+['"]([^'"]+)['"];''', multiLine: true);
    final partOf = RegExp(r'''^part of\s+['"]([^'"]+)['"];''', multiLine: true);
    for (final entry in _dartFiles('lib')) {
      final parts = partDirective.allMatches(entry.readAsStringSync()).toList();
      if (parts.isEmpty) continue;
      final component = _path(entry.parent);
      final expected = <String>{_path(entry)};
      for (final directive in parts) {
        expect(
          Uri.parse(directive[1]!).hasScheme,
          isFalse,
          reason: '${entry.path}: part directives stay relative to their owning component',
        );
        final file = _resolve(entry, directive[1]!);
        expect(
          _path(file).startsWith('$component/'),
          isTrue,
          reason: '${entry.path}: parts must stay inside their component',
        );
        expect(file.existsSync(), isTrue, reason: file.path);
        final owner = partOf.firstMatch(file.readAsStringSync());
        expect(owner, isNotNull, reason: file.path);
        expect(
          Uri.parse(owner![1]!).hasScheme,
          isFalse,
          reason: '${file.path}: part of directives stay relative to their owning library',
        );
        expect(_path(_resolve(file, owner[1]!)), _path(entry));
        expected.add(_path(file));
      }
      final actual = _dartFiles(entry.parent.path).map(_path).toSet();
      expect(actual, expected, reason: '${entry.path}: move independent libraries outside this component directory');
    }
  });

  test('data definitions and data operations do not depend on app or UI', () {
    final forbidden = RegExp(
      r'''^(?:import|export)\s+['"]package:phonolite_app/(?:application|pages|ui|bootstrap)/''',
      multiLine: true,
    );
    for (final file in _dartFiles('lib/data')) {
      expect(forbidden.allMatches(file.readAsStringSync()), isEmpty, reason: file.path);
    }
    for (final area in ['models', 'rules', 'queries', 'projections', 'structures', 'configuration', 'files']) {
      for (final file in _dartFiles('lib/data/$area')) {
        expect(
          file.readAsStringSync(),
          isNot(matches(r'^part of\s')),
          reason: '${file.path}: reusable data modules must be standalone libraries',
        );
      }
    }
    for (final legacy in [
      'lib/domain',
      'lib/infrastructure/storage',
      'lib/infrastructure/repositories',
      'lib/infrastructure/logging',
      'lib/infrastructure/server/models',
    ]) {
      expect(Directory(legacy).existsSync(), isFalse, reason: '$legacy: data has one designated source area');
    }
  });
}

Iterable<File> _dartFiles(String directory) =>
    Directory(directory).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));

String _path(FileSystemEntity entity) => entity.absolute.path.replaceAll('\\', '/');

File _resolve(File source, String uri) => uri.startsWith('package:phonolite_app/')
    ? File('lib/${uri.substring('package:phonolite_app/'.length)}')
    : File.fromUri(source.absolute.uri.resolve(uri));
