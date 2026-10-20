import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/report_channel.dart';

void main() {
  test(
    'reports remain available until the host acknowledges saving them',
    () async {
      final channel = UiReportChannel();
      var saved = false;
      final published = channel.publish({'type': 'journey_result'}).then((_) {
        saved = true;
      });
      final first = await channel.receive();
      expect(saved, isFalse);
      expect(await channel.receive(acknowledge: 999), first);
      expect(saved, isFalse);
      await channel.receive(
        acknowledge: first['sequence'] as int,
        wait: Duration.zero,
      );
      await published;
      expect(saved, isTrue);
      expect(await channel.receive(wait: Duration.zero), isEmpty);
    },
  );

  test('the next result cannot overwrite an unsaved result', () async {
    final channel = UiReportChannel();
    final published = channel.publish({'id': 'first'});
    await expectLater(channel.publish({'id': 'second'}), throwsStateError);
    final first = await channel.receive();
    expect((first['event'] as Map)['id'], 'first');
    await channel.receive(
      acknowledge: first['sequence'] as int,
      wait: Duration.zero,
    );
    await published;
  });
}
