package com.phonoliteorg.phonolite_app.infrastructure.audio

import java.util.concurrent.atomic.AtomicLong

// The session monitor serializes observations and resets. The writer only
// changes the atomic ledgers while holding the session's write lock.
@Suppress("UNUSED_PARAMETER")
internal class AudioPlaybackProgress(
  private val playbackProbe: AudioPlaybackProbe,
  sampleRateHz: Int,
  private val bytesPerFrame: Int,
  private val bytesPerSample: Int = 2,
  monotonicTimeNs: () -> Long = System::nanoTime
) {
  private companion object {
    const val PLAYBACK_HEAD_MASK = 0xFFFFFFFFL
    const val PLAYBACK_HEAD_HALF_RANGE = 0x80000000L
  }

  private val pendingFrames = AtomicLong(0)
  private val totalWrittenFrames = AtomicLong(0)
  private var lastRawPlaybackHead = 0L
  private var playbackHeadOffset = 0L
  private var timestampOffset = 0L
  private var timestampsSynchronized = true
  private var clockReset = false
  private var lastReportedPlaybackHead = 0L
  private var uncollectedFrames = 0L

  // Only renderer observations can complete audio. In particular, elapsed
  // playing time during an underrun must not advance track markers/listening.
  fun markPlaying() = Unit

  fun markPaused() = Unit

  fun consumeClockReset(): Boolean {
    val reset = clockReset
    clockReset = false
    return reset
  }

  fun resetForFlush() {
    pendingFrames.set(0L)
    totalWrittenFrames.set(0L)
    lastRawPlaybackHead = 0L
    playbackHeadOffset = 0L
    timestampOffset = 0L
    timestampsSynchronized = true
    clockReset = false
    lastReportedPlaybackHead = 0L
  }

  fun pendingFrameCount(): Long = pendingFrames.get()

  fun addPendingFrames(frames: Long) {
    pendingFrames.addAndGet(frames)
  }

  fun recordWrittenBytes(bytes: Int) {
    totalWrittenFrames.addAndGet((bytes / bytesPerFrame).toLong())
  }

  fun discardPendingFrames(frames: Int) {
    pendingFrames.updateAndGet { current -> (current - frames).coerceAtLeast(0L) }
  }

  fun collectDoneSamples(): Int {
    pollCompletedFrames()

    // Writes, pauses and idle checks also poll. Completed frames remain here
    // until the engine explicitly consumes them, including across a flush.
    val channels = bytesPerFrame / bytesPerSample
    val maximumFrames = Int.MAX_VALUE.toLong() / channels
    val doneFrames = minOf(uncollectedFrames, maximumFrames)
    uncollectedFrames -= doneFrames

    return (doneFrames * channels).toInt()
  }

  fun pollCompletedFrames(): Long {
    val raw = playbackProbe.playbackHeadPosition() and PLAYBACK_HEAD_MASK

    if (raw < lastRawPlaybackHead) {
      if (lastRawPlaybackHead - raw > PLAYBACK_HEAD_HALF_RANGE) {
        playbackHeadOffset += 1L shl 32
      } else {
        // A reset is not a 2^32-frame wrap. Rebase conservatively at the
        // previous confirmed position, and ignore stale pre-reset timestamps.
        playbackHeadOffset = lastReportedPlaybackHead - raw
        timestampOffset = playbackHeadOffset
        timestampsSynchronized = false
        clockReset = true
      }
    }

    lastRawPlaybackHead = raw
    var absoluteReportedHead = playbackHeadOffset + raw
    val timestampHead = playbackProbe.timestampFramePosition()

    if (!timestampsSynchronized && timestampHead != null && timestampHead <= raw) {
      timestampsSynchronized = true
    }
    if (timestampsSynchronized && timestampHead != null) {
      absoluteReportedHead = maxOf(absoluteReportedHead, timestampOffset + timestampHead)
    }

    val writtenFrames = totalWrittenFrames.get()
    val absoluteHead =
      absoluteReportedHead.coerceIn(lastReportedPlaybackHead, maxOf(writtenFrames, lastReportedPlaybackHead))
    val deltaFrames = (absoluteHead - lastReportedPlaybackHead).coerceAtLeast(0L)

    if (deltaFrames > 0L) {
      uncollectedFrames += deltaFrames
      lastReportedPlaybackHead = absoluteHead
      pendingFrames.updateAndGet { current ->
        if (current <= deltaFrames) {
          0L
        } else {
          current - deltaFrames
        }
      }
    }

    return deltaFrames
  }
}
