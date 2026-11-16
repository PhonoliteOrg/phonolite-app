import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/audio/output/pcm_queue_writer.dart';

void main() {
  PcmQueueWriter writer() => PcmQueueWriter(retryDelay: const Duration(milliseconds: 1));

  test('a full queue is retried until the chunk is queued', () async {
    final writes = writer();
    final replies = [PcmQueueStatus.full, PcmQueueStatus.full, PcmQueueStatus.queued];
    var attempts = 0;

    await writes.queue(writes.begin(), targetIsOpen: () => true, attempt: () => replies[attempts++]);

    expect(attempts, 3);
  });

  test('cancelling stops a write that is waiting for capacity', () async {
    final writes = writer();
    var attempts = 0;
    final write = writes.queue(
      writes.begin(),
      targetIsOpen: () => true,
      attempt: () {
        attempts++;

        return PcmQueueStatus.full;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    writes.cancelPending();
    await write;

    final attemptsAtCancel = attempts;

    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(attemptsAtCancel, greaterThan(0));
    expect(attempts, attemptsAtCancel);
  });

  test('a write cancelled before it reaches the queue makes no attempt', () async {
    final writes = writer();
    final write = writes.begin();
    var attempts = 0;

    writes.cancelPending();
    await writes.queue(
      write,
      targetIsOpen: () => true,
      attempt: () {
        attempts++;

        return PcmQueueStatus.queued;
      },
    );

    expect(attempts, 0);
  });

  test('a closed target stops retrying without an error', () async {
    final writes = writer();
    var open = true;
    var attempts = 0;

    await writes.queue(
      writes.begin(),
      targetIsOpen: () => open,
      attempt: () {
        attempts++;
        open = false;

        return PcmQueueStatus.full;
      },
    );

    expect(attempts, 1);
  });

  test('a native failure for a current write is reported', () async {
    final writes = writer();
    final failure = StateError('native write failed');

    await expectLater(
      writes.queue(writes.begin(), targetIsOpen: () => true, attempt: () => throw failure),
      throwsA(same(failure)),
    );
  });

  test('a failure reported after the write was cancelled is ignored', () async {
    final writes = writer();
    final reply = Completer<PcmQueueStatus>();
    final write = writes.queue(writes.begin(), targetIsOpen: () => true, attempt: () => reply.future);

    writes.cancelPending();
    reply.completeError(StateError('stale write failed'));

    await write;
  });

  test('cancelling does not affect a write that starts afterwards', () async {
    final writes = writer();

    writes.cancelPending();

    var attempts = 0;

    await writes.queue(
      writes.begin(),
      targetIsOpen: () => true,
      attempt: () {
        attempts++;

        return PcmQueueStatus.queued;
      },
    );

    expect(attempts, 1);
  });
}
