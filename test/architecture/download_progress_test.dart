import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/entities/download_progress_throttle.dart';

void main() {
  const interval = Duration(milliseconds: 200);

  test('a small transfer reports intermediate progress before completing', () {
    final throttle = DownloadProgressThrottle(interval: interval);
    const totalBytes = 64 * 1024;
    final fractions = <double>[];
    for (var chunk = 1; chunk <= 16; chunk++) {
      final received = chunk * 4096;
      if (throttle.shouldReport(
        receivedBytes: received,
        elapsed: Duration(milliseconds: chunk * 50),
      )) {
        fractions.add(received / totalBytes);
      }
    }
    expect(fractions, containsAllInOrder([0.25, 0.5, 0.75, 1.0]));
  });

  test('a slow transfer reports even single-byte advances', () {
    final throttle = DownloadProgressThrottle(interval: interval);
    for (var received = 1; received <= 5; received++) {
      expect(
        throttle.shouldReport(
          receivedBytes: received,
          elapsed: Duration(seconds: received),
        ),
        isTrue,
      );
    }
  });

  test('fast chunks are coalesced and do not report unchanged bytes', () {
    final throttle = DownloadProgressThrottle(interval: interval);
    var reports = 0;
    for (var chunk = 1; chunk <= 1000; chunk++) {
      if (throttle.shouldReport(
        receivedBytes: chunk * 1024,
        elapsed: Duration(milliseconds: chunk),
      )) {
        reports++;
      }
    }
    expect(reports, 5);
    expect(
      throttle.shouldReport(
        receivedBytes: 1000 * 1024,
        elapsed: const Duration(seconds: 2),
      ),
      isFalse,
    );
  });

  test('resumed transfers retain their offset and flush final progress', () {
    final throttle = DownloadProgressThrottle(
      interval: interval,
      initialBytes: 1024,
    );
    expect(
      throttle.shouldReport(receivedBytes: 1536, elapsed: interval),
      isTrue,
    );
    expect(
      throttle.shouldReport(
        receivedBytes: 2048,
        elapsed: const Duration(milliseconds: 250),
      ),
      isFalse,
    );
    expect(
      throttle.shouldReport(
        receivedBytes: 2048,
        elapsed: const Duration(milliseconds: 250),
        force: true,
      ),
      isTrue,
    );
    expect(
      throttle.shouldReport(
        receivedBytes: 2048,
        elapsed: const Duration(milliseconds: 250),
        force: true,
      ),
      isFalse,
    );
  });
}
