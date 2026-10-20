import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_capture.dart';

void main() {
  test(
    'stream history and snapshot tail merge without losing early events',
    () {
      final capture = UiTimelineCapture(100);
      capture.add({'ts': 90, 'name': 'previous journey'});
      capture.add({
        'ts': 100,
        'name': 'early jank',
        'args': {'b': 2, 'a': 1},
      });
      capture.add({'ts': 200, 'name': 'later frame'});
      // Simulate a ring snapshot whose oldest streamed events were overwritten.
      capture.add({'name': 'later frame', 'ts': 200});
      capture.add({'ts': 300, 'name': 'unstreamed tail'});
      capture.add({'ts': 400, 'name': 'after capture'});
      final result = capture.finish(300);
      final events = result['traceEvents'] as List;
      expect(events.map((event) => event['name']), [
        'early jank',
        'later frame',
        'unstreamed tail',
      ]);
      expect((result['capture'] as Map)['event_count'], 3);
    },
  );

  test(
    'deduplication preserves distinct event arguments and thread metadata',
    () {
      final capture = UiTimelineCapture(100);
      capture.add({'ph': 'M', 'ts': 0, 'name': 'thread_name'});
      capture.add({
        'ts': 100,
        'name': 'work',
        'args': {'b': 2, 'a': 1},
      });
      capture.add({
        'name': 'work',
        'args': {'a': 1, 'b': 2},
        'ts': 100,
      });
      capture.add({
        'ts': 100,
        'name': 'work',
        'args': {'a': 3, 'b': 2},
      });
      expect((capture.finish(200)['traceEvents'] as List).length, 3);
    },
  );
}
