import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/infrastructure/audio/engine/audio_engine.dart';
import 'package:phonolite_quic/phonolite_quic.dart';

import '../support/streaming_test_helpers.dart';

class _RejectedOpen extends MemoryQuic {
  @override
  int openTrack({
    required String trackId,
    String? mode,
    String? quality,
    int frameMs = 20,
    List<String> queue = const [],
    int startMs = 0,
  }) => throw QuicException('Untrusted server identity.', kind: QuicFailureKind.identity);
}

class _RejectedContinuation extends MemoryQuic {
  @override
  int seek({required String trackId, required int positionMs, required int seekId}) =>
      throw QuicException('Source authorization was revoked.', kind: QuicFailureKind.sourceRejected);
}

class _RejectedRead extends MemoryQuic {
  @override
  int read(Uint8List buffer) => throw QuicException('Untrusted server identity.', kind: QuicFailureKind.identity);
}

void main() {
  for (final (description, makeTransport) in <(String, MemoryQuic Function())>[
    ('initial Open', _RejectedOpen.new),
    ('range continuation', _RejectedContinuation.new),
    ('read before native failure classification', _RejectedRead.new),
  ]) {
    test('terminal $description rejects the source without reconnecting', () async {
      final transport = makeTransport();
      transport.onRequest = (start, seekId) => transport.deliverRange(startMs: start, endMs: 400);
      var replacements = 0;
      final harness = AudioPlaybackHarness(
        transport: transport,
        connectionFactory: () {
          replacements++;
          return MemoryQuic();
        },
        decoderFactory: MemoryOpusDecoder.new,
        outputFactory: (_, __, ___) => MemoryPcmOutput(),
      );
      addTearDown(harness.close);

      harness.start();
      await waitUntil(() => harness.messages.any((event) => event['source_rejected'] == true));

      expect(replacements, 0);
      expect(harness.messages.where((event) => event['type'] == 'complete'), isEmpty);
      expect(transport.closed, isTrue);
    });
  }

  test('an identity failure creating a replacement cannot enter controller transport retry', () async {
    final transport = MemoryQuic();
    transport.onRequest = (start, seekId) {
      transport.deliverRange(startMs: start, endMs: 400, packetCount: 10, complete: false);
      transport.closed = true;
    };
    var replacements = 0;
    final harness = AudioPlaybackHarness(
      transport: transport,
      connectionFactory: () {
        replacements++;
        throw ServerIdentityChangedException();
      },
      decoderFactory: MemoryOpusDecoder.new,
      outputFactory: (_, __, ___) => MemoryPcmOutput(),
    );
    addTearDown(harness.close);

    harness.start();
    await waitUntil(() => harness.messages.any((event) => event['source_rejected'] == true));

    expect(replacements, 1);
    expect(harness.messages.where((event) => event['type'] == 'complete'), isEmpty);
  });
}
