import 'dart:async';

/// What a native output reported for one attempt to queue a PCM chunk.
enum PcmQueueStatus { queued, full }

/// Cancellable writes into a native queue that accepts whole PCM chunks.
///
/// Flush and disposal call [cancelPending]. A write that started earlier stops
/// retrying, and whatever the device reports for it afterwards is ignored, so a
/// superseded write never fails the playback that replaced it. Outputs supply
/// the native attempt and the retry delay that suits their transport.
final class PcmQueueWriter {
  final Duration retryDelay;
  int _generation = 0;

  PcmQueueWriter({required this.retryDelay});

  /// Cancels every write started before this call.
  void cancelPending() => _generation++;

  /// Marks the start of one write. Call it before any await so a flush during
  /// output startup also cancels the write.
  int begin() => _generation;

  /// Queues one chunk, retrying after [retryDelay] while the queue is full.
  ///
  /// Stops without error once [write] is cancelled or [targetIsOpen] reports
  /// that the native target it writes to has closed or been replaced.
  /// [attempt] throws for a native failure.
  Future<void> queue(
    int write, {
    required bool Function() targetIsOpen,
    required FutureOr<PcmQueueStatus> Function() attempt,
  }) async {
    bool isCurrent() => write == _generation && targetIsOpen();

    while (isCurrent()) {
      final PcmQueueStatus status;

      try {
        status = await attempt();
      } catch (_) {
        if (!isCurrent()) {
          return;
        }

        rethrow;
      }

      if (status == PcmQueueStatus.queued || !isCurrent()) {
        return;
      }

      await Future<void>.delayed(retryDelay);
    }
  }
}
