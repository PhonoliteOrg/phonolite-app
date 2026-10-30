import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/accessibility_update_binding.dart';

void main() {
  final binding = AccessibilityUpdateBinding();

  setUp(binding.resetAccessibilityTree);

  void initialTree() => binding.applyAccessibilityUpdate({
    0: [1, 2],
    1: [3],
    2: [],
    3: [31],
    31: [],
  });

  test('reparenting requires unchanged descendants to be serialized again', () {
    initialTree();

    expect(
      () => binding.applyAccessibilityUpdate({
        1: [],
        2: [3],
        3: [31],
      }),
      throwsA(isA<TestFailure>().having((failure) => failure.message, 'missing descendant', contains('pending'))),
    );
  });

  test('reparenting accepts a complete subtree in the same update', () {
    initialTree();
    binding.applyAccessibilityUpdate({
      1: [],
      2: [3],
      3: [31],
      31: [],
    });
  });

  test('captured Windows startup rejects the omitted slider popup', () {
    final updates = _readUpdates('test/fixtures/accessibility/windows_startup_reparent.txt');

    for (final update in updates.take(updates.length - 1)) {
      binding.applyAccessibilityUpdate(update);
    }

    expect(
      () => binding.applyAccessibilityUpdate(updates.last),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'pending popup',
          allOf(contains('pending'), contains('31')),
        ),
      ),
    );
  });

  test('captured Windows startup accepts the complete slider popup update', () {
    for (final update in _readUpdates('test/fixtures/accessibility/windows_startup_reparent_complete.txt')) {
      binding.applyAccessibilityUpdate(update);
    }
  });
}

List<Map<int, List<int>>> _readUpdates(String path) {
  final lines = File(path).readAsLinesSync();
  final updates = <Map<int, List<int>>>[];

  for (var index = 0; index < lines.length; index++) {
    if (lines[index] == 'R') {
      continue;
    }

    final header = lines[index].split(' ');

    expect(header.first, 'B');

    final update = <int, List<int>>{};
    final count = int.parse(header[1]);

    for (var node = 0; node < count; node++) {
      final fields = lines[++index].split(' ').map(int.parse).toList();

      expect(fields.length, fields[1] + 2);
      update[fields[0]] = fields.skip(2).toList();
    }

    updates.add(update);
  }

  return updates;
}
