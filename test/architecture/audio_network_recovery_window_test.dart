import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/structures/audio/audio_network_recovery_window.dart';

void main() {
  test('improved LTE delivery relaxes protection using elapsed time despite irregular polls', () {
    final window = AudioNetworkRecoveryWindow();
    bool observe(int nowMs, int level) => window.observe(
      now: Duration(milliseconds: nowMs),
      level: level,
      rttMs: level == 2 ? 220 : 90,
      bufferedMs: 2000,
      minimumReserveMs: level == 2 ? 1500 : 600,
      acceptedThroughMs: nowMs + 2000,
      readAheadSatisfied: false,
      userPaused: false,
    );

    expect(observe(0, 2), isFalse);
    expect(observe(100, 2), isFalse);
    expect(observe(2900, 2), isFalse);
    expect(observe(3100, 2), isTrue);
    expect(observe(3200, 1), isFalse);
    expect(observe(8100, 1), isFalse);
    expect(observe(8300, 1), isTrue);
  });

  test('low latency alone cannot relax a connection delivering too little audio', () {
    final window = AudioNetworkRecoveryWindow();
    for (var ms = 0; ms <= 12000; ms += 250) {
      expect(
        window.observe(
          now: Duration(milliseconds: ms),
          level: 2,
          rttMs: 60,
          bufferedMs: 1800,
          minimumReserveMs: 1500,
          acceptedThroughMs: ms ~/ 3 + 1800,
          readAheadSatisfied: false,
          userPaused: false,
        ),
        isFalse,
      );
    }
  });

  test('recovery reserve respects a source with a small byte-capped PCM horizon', () {
    final window = AudioNetworkRecoveryWindow();
    bool observe(int ms) => window.observe(
      now: Duration(milliseconds: ms),
      level: 2,
      rttMs: 100,
      bufferedMs: 400,
      minimumReserveMs: 400,
      acceptedThroughMs: ms + 400,
      readAheadSatisfied: false,
      userPaused: false,
    );

    expect(observe(0), isFalse);
    expect(observe(3000), isTrue);
  });

  for (final draining in [false, true]) {
    test(
      'a bounded full queue ${draining ? 'cannot hide reserve loss' : 'can recover without demanding more bytes'}',
      () {
        final window = AudioNetworkRecoveryWindow();
        expect(
          window.observe(
            now: Duration.zero,
            level: 2,
            rttMs: 100,
            bufferedMs: 4000,
            minimumReserveMs: 1500,
            acceptedThroughMs: 4000,
            readAheadSatisfied: true,
            userPaused: false,
          ),
          isFalse,
        );
        expect(
          window.observe(
            now: const Duration(seconds: 3),
            level: 2,
            rttMs: 100,
            bufferedMs: draining ? 2000 : 4000,
            minimumReserveMs: 1500,
            acceptedThroughMs: 4000,
            readAheadSatisfied: true,
            userPaused: false,
          ),
          !draining,
        );
      },
    );
  }

  for (final interruption in ['latency', 'reserve', 'pause', 'seek']) {
    test('$interruption interrupts a healthy recovery window', () {
      final window = AudioNetworkRecoveryWindow();
      bool observe(int ms, {bool interrupt = false}) => window.observe(
        now: Duration(milliseconds: ms),
        level: 2,
        rttMs: interrupt && interruption == 'latency' ? 650 : 100,
        bufferedMs: interrupt && interruption == 'reserve' ? 100 : 2000,
        minimumReserveMs: 1500,
        acceptedThroughMs: interrupt && interruption == 'seek' ? 1000 : 5000 + ms,
        readAheadSatisfied: false,
        userPaused: interrupt && interruption == 'pause',
      );

      expect(observe(0), isFalse);
      expect(observe(2500, interrupt: true), isFalse);
      expect(observe(3000), isFalse);
      expect(observe(5500), interruption == 'seek');
      if (interruption != 'seek') {
        expect(observe(6100), isTrue);
      }
    });
  }
}
