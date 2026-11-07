import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/rules/audio/audio_recovery_policy.dart';
import 'package:phonolite_app/data/structures/audio/audio_network_history.dart';

void main() {
  test('network observations persist across sources and expire per endpoint', () {
    var now = Duration.zero;
    final history = AudioNetworkHistory(now: () => now);
    history.remember('cellular-server', 2);
    expect(history.levelFor('cellular-server'), 2);
    expect(history.levelFor('other-server'), 0);
    now += AudioNetworkHistory.lifetime;
    expect(history.levelFor('cellular-server'), 0);
  });

  test('history evicts old endpoints and never grows without a bound', () {
    final history = AudioNetworkHistory();
    for (var i = 0; i <= AudioNetworkHistory.maximumEntries; i++) {
      history.remember('$i', 2);
    }
    expect(history.levelFor('0'), 0);
    expect(history.levelFor('${AudioNetworkHistory.maximumEntries}'), 2);
  });

  test('delivery stall deadlines leave time for latency and loss recovery', () {
    const policy = AudioRecoveryPolicy();
    expect(policy.stallTimeout(playableMilliseconds: 800), const Duration(seconds: 5));
    expect(policy.stallTimeout(playableMilliseconds: 800, rttMilliseconds: 1500), const Duration(seconds: 9));
    expect(policy.stallTimeout(playableMilliseconds: 800, rttMilliseconds: 10000), const Duration(seconds: 12));
  });

  test('healthy playable progress clears recovery at the effective refill target', () {
    var now = Duration.zero;
    const policy = AudioRecoveryPolicy();
    final episode = AudioRecoveryEpisode(now: () => now)..begin(0);
    episode.reserveAttempt();
    final reserve = policy.healthyReserveMilliseconds(600);
    episode.observe(acceptedThrough: 600, playableMilliseconds: 800, requiredReserveMilliseconds: reserve);
    now += AudioRecoveryPolicy.healthyPeriod;
    episode.observe(acceptedThrough: 2600, playableMilliseconds: 800, requiredReserveMilliseconds: reserve);
    expect(episode.active, isFalse);
  });
}
