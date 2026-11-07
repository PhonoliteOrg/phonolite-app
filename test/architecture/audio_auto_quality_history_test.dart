import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/structures/audio/audio_auto_quality_history.dart';

AudioAutoQualityScope _scope({String token = 'alice', int route = 0, String endpoint = 'https://server'}) =>
    AudioAutoQualityHistory.scope(endpoint: endpoint, token: token, serverPin: 'pin', routeGeneration: route);

void main() {
  test('Original preference survives skips but expires and stays account and route scoped', () {
    var now = Duration.zero;
    final history = AudioAutoQualityHistory(now: () => now);
    final scope = _scope();
    expect(history.mayWarmOriginal(scope), isFalse);
    history.rememberOriginal(scope);
    expect(history.mayWarmOriginal(_scope()), isTrue);
    expect(history.mayWarmOriginal(_scope(token: 'bob')), isFalse);
    expect(history.mayWarmOriginal(_scope(route: 1)), isFalse);
    expect(history.mayWarmOriginal(_scope(endpoint: 'https://other-server')), isFalse);
    now = AudioAutoQualityHistory.lifetime;
    expect(history.mayWarmOriginal(scope), isFalse);
  });

  test('network pressure survives skips and old queued Original cannot erase the cooldown', () {
    var now = Duration.zero;
    final history = AudioAutoQualityHistory(now: () => now);
    final scope = _scope();
    history.rememberOriginal(scope);
    history.deferOriginal(scope);
    history.rememberOriginal(scope);
    expect(history.mayWarmOriginal(scope), isFalse);
    expect(history.mayProbeOriginal(scope), isFalse);
    now = AudioAutoQualityHistory.retryDelay;
    expect(history.mayProbeOriginal(scope), isTrue);
    expect(history.mayWarmOriginal(scope), isFalse);
    history.rememberOriginal(scope);
    expect(history.mayWarmOriginal(scope), isTrue);
  });

  test('history keeps only a bounded number of recently observed listeners and routes', () {
    final history = AudioAutoQualityHistory();
    for (var route = 0; route <= AudioAutoQualityHistory.maximumEntries; route++) {
      history.rememberOriginal(_scope(route: route));
    }
    expect(history.mayWarmOriginal(_scope(route: 0)), isFalse);
    expect(history.mayWarmOriginal(_scope(route: 1)), isTrue);
    expect(history.mayWarmOriginal(_scope(route: AudioAutoQualityHistory.maximumEntries)), isTrue);
  });
}
