import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String projectPath(String relativePath) {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  return '${Directory.current.path}${Platform.pathSeparator}$normalized';
}

String readProjectFile(String relativePath) {
  final file = File(projectPath(relativePath));
  if (!file.existsSync()) {
    throw StateError('Expected source file to exist: $relativePath');
  }
  return file.readAsStringSync();
}

void expectContainsAll(String source, Iterable<String> snippets) {
  for (final snippet in snippets) {
    expect(
      source,
      contains(snippet),
      reason: 'Expected source to contain `$snippet`.',
    );
  }
}
