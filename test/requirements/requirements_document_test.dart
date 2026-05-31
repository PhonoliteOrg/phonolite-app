import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('requirements document', () {
    final requirements = readProjectFile('REQUIREMENTS.md');

    test('exists with the expected top-level sections', () {
      expectContainsAll(requirements, const [
        '# Phonolite App Requirements',
        '## Application Shell and Visual System',
        '## Startup, Session, and Authentication',
        '## Navigation and App Structure',
        '## Library Browsing and Search',
        '## Playback, Queueing, and Transport Control',
        '## Android Platform Requirements',
        '## iOS Platform Requirements',
        '## macOS Platform Requirements',
        '## Windows Platform Requirements',
      ]);
    });

    test('uses unique requirement ids across all requirement groups', () {
      final ids = RegExp(
        r'\b[A-Z]+-\d{3}\b',
      ).allMatches(requirements).map((match) => match.group(0)!).toList();

      expect(ids.length, greaterThan(100));
      expect(ids.toSet().length, ids.length);
      expect(
        ids.any((id) => id.startsWith('UI-')),
        isTrue,
        reason: 'Expected UI requirement ids.',
      );
      expect(
        ids.any((id) => id.startsWith('PLAY-')),
        isTrue,
        reason: 'Expected playback requirement ids.',
      );
      expect(
        ids.any((id) => id.startsWith('NET-')),
        isTrue,
        reason: 'Expected network requirement ids.',
      );
      expect(
        ids.any((id) => id.startsWith('IOS-')),
        isTrue,
        reason: 'Expected iOS requirement ids.',
      );
    });
  });
}
