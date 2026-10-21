import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pageStructures = {
  'lib/ui/shell/base_page.dart',
  'lib/ui/shell/base_form_page.dart',
};

void main() {
  test('pages and UI use controllers and data values, never concrete I/O', () {
    for (final file in [..._dartFiles('lib/pages'), ..._dartFiles('lib/ui')]) {
      expect(
        _dependencies(file).where(
          (path) =>
              path.startsWith('lib/infrastructure/') ||
              path.startsWith('lib/bootstrap/') ||
              const [
                'lib/data/storage/',
                'lib/data/repositories/',
                'lib/data/files/',
                'lib/data/configuration/',
              ].any(path.startsWith),
        ),
        isEmpty,
        reason: file.path,
      );
    }
  });

  test('page assembly stays above UI components and functional layers', () {
    for (final area in ['ui', 'application', 'data', 'infrastructure']) {
      for (final file in _dartFiles('lib/$area')) {
        expect(
          _dependencies(file).where((path) => path.startsWith('lib/pages/')),
          isEmpty,
          reason:
              '${file.path}: pages assemble components and own route choices',
        );
      }
    }
    for (final file in _dartFiles('lib/ui')) {
      if (_pageStructures.contains(file.path.replaceAll('\\', '/'))) {
        expect(
          file.readAsStringSync(),
          isNot(matches(RegExp(r'^class \w*Page\b', multiLine: true))),
          reason: 'Shared page structures must remain abstract.',
        );
        continue;
      }
      expect(
        file.path,
        isNot(matches(r'(?:_page|_screen|_detail_view)\.dart$')),
        reason: 'Page entry points belong in lib/pages.',
      );
    }
  });

  test('shared structures remain independent of concrete feature owners', () {
    for (final file in [
      ..._dartFiles('lib/ui/structures'),
      ..._pageStructures.map(File.new),
      File('lib/ui/shell/page_body.dart'),
      File('lib/ui/shell/page_scroll_view.dart'),
      ..._dartFiles('lib/ui/shell/toolbars'),
      ..._dartFiles('lib/ui/shell/navigation'),
    ]) {
      expect(
        _dependencies(file).where(
          (path) =>
              path.startsWith('lib/application/') ||
              path.startsWith('lib/ui/features/'),
        ),
        isEmpty,
        reason: '${file.path}: supply feature content through extension hooks',
      );
    }
    for (final file in _dartFiles('lib/pages')) {
      expect(
        file.readAsStringSync(),
        matches(r'extends (?:BasePage|BaseStatelessPage)\b'),
        reason: '${file.path}: pages share the presentation assembly contract',
      );
    }
  });

  test('base page owns toolbar placement and page viewport assembly', () {
    final pageViewports = RegExp(
      r'\b(?:Scaffold|PageScrollView|CustomScrollView|SingleChildScrollView)\s*\(',
    );
    for (final file in _dartFiles('lib/pages')) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(pageViewports)),
        reason: '${file.path}: supply PageBody instead of rebuilding the frame',
      );
      expect(
        source,
        anyOf(
          matches(r'\bWidget\s+pageContent\s*\('),
          contains('extends BaseFormPageState<'),
        ),
        reason: '${file.path}: use the base page assembly contract',
      );
      expect(
        _dependencies(
          file,
        ).where((path) => path.startsWith('lib/ui/shell/navigation/')),
        isEmpty,
        reason: '${file.path}: the app shell owns destination surfaces',
      );
    }
    for (final path in [
      ..._pageStructures,
      'lib/ui/shell/page_body.dart',
      'lib/ui/shell/page_scroll_view.dart',
    ]) {
      expect(
        _dependencies(
          File(path),
        ).where((path) => path.startsWith('lib/ui/shell/navigation/')),
        isEmpty,
        reason: '$path: page frames do not own app navigation',
      );
    }
  });

  test(
    'page toolbars and app navigation are independent presentation families',
    () {
      for (final (family, other) in [
        ('toolbars', 'navigation'),
        ('navigation', 'toolbars'),
      ]) {
        for (final file in _dartFiles('lib/ui/shell/$family')) {
          expect(
            _dependencies(
              file,
            ).where((path) => path.startsWith('lib/ui/shell/$other/')),
            isEmpty,
            reason:
                '${file.path}: page actions and app destinations have separate owners',
          );
        }
      }
    },
  );

  test(
    'feature controllers have no widget, routing or visual lifecycle dependencies',
    () {
      final forbidden = RegExp(
        r'\b(BuildContext|Widget|StatefulWidget|StatelessWidget|Navigator|TextEditingController|ScrollController|AnimationController|WidgetsBinding|showDialog|setState)\b',
      );
      for (final file
          in Directory('lib/application/controllers')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('package:phonolite_app/ui/')),
          reason: file.path,
        );
        expect(
          source,
          isNot(contains('package:flutter/material.dart')),
          reason: file.path,
        );
        expect(
          forbidden.allMatches(source).map((match) => match[0]),
          isEmpty,
          reason: file.path,
        );
      }
    },
  );
}

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Iterable<String> _dependencies(File file) sync* {
  final directives = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final root = Directory.current.absolute.uri;
  for (final match in directives.allMatches(file.readAsStringSync())) {
    final uri = match[1]!;
    if (uri.startsWith('package:phonolite_app/')) {
      yield 'lib/${uri.substring('package:phonolite_app/'.length)}';
    } else if (!Uri.parse(uri).hasScheme) {
      final resolved = file.absolute.uri.resolve(uri).toString();
      if (resolved.startsWith(root.toString())) {
        yield Uri.decodeComponent(resolved.substring(root.toString().length));
      }
    }
  }
}
