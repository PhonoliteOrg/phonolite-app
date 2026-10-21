import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/listening_stats/listening_counters.dart';
import 'package:phonolite_app/data/repositories/listening_stats_service.dart';

void main() {
  test('frozen batches preserve unknown wire fields without writable aliases', () {
    final input = <String, dynamic>{
      'batch_sequence': 7,
      'metadata': {
        'track': {
          'genres': ['Rock'],
        },
      },
      'future_field': [3, null, false],
    };
    final batch = ListeningCounterBatch.fromJson(input);
    final original = batch.toJson();

    ((input['metadata'] as Map)['track']['genres'] as List).add('Jazz');
    (input['future_field'] as List).clear();

    expect(batch.batchSequence, 7);
    expect(batch.toJson(), original);

    final exported = batch.toJson();

    ((exported['metadata'] as Map)['track']['genres'] as List).clear();
    (exported['future_field'] as List).add('changed');

    expect(batch.toJson(), original);
  });

  test('checkpoint decoding retains its exact optional wire keys', () {
    final checkpoint = ListeningCounterCheckpoint.fromJson({'last_sequence': 4});

    expect(checkpoint.lastSequence, 4);
    expect(checkpoint.upgraded, isFalse);
    expect(checkpoint.toJson(), {'last_sequence': 4});
  });

  test('typed state owns its month snapshot and distinguishes a missing generation', () {
    final months = [
      {'year': 2026, 'month': 10, 'revision': 9},
    ];
    final state = ListeningCounterState.fromJson({
      'server_id': 'server',
      'user_id': 'user',
      'checkpoint': {'last_sequence': 2, 'upgraded': true},
      'months': months,
    });

    months.clear();

    expect(state.historyGeneration, isNull);
    expect(state.months.single.key, '2026:10');
    expect(state.months.single.revision, 9);
    expect(() => state.months.clear(), throwsUnsupportedError);
  });

  test('typed repository commands retain durable consent and account scoping', () async {
    final history = ListeningStatsService(inMemory: true);

    try {
      await history.initialize();
      await history.setAccount(serverId: 'server', userId: 'user');

      expect(await history.counterConsent(), -1);

      await history.acknowledgeCounterConsent(3);

      expect(await history.counterConsent(), 3);
      expect(await history.counterMonths(), isEmpty);
      expect(await history.prepareCounterBatch(collectionRevision: 0), isNull);

      await history.setAccount(serverId: 'server', userId: 'other');

      expect(await history.counterConsent(), -1);
    } finally {
      await history.close();
    }
  });
}
