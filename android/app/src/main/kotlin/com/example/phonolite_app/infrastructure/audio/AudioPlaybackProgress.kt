package com.example.phonolite_app.infrastructure.audio

import java.util.concurrent.atomic.AtomicLong

// The session monitor serializes observations and resets. The writer only
// changes the atomic ledgers while holding the session's write lock.
internal class AudioPlaybackProgress(
  private val playbackProbe: AudioPlaybackProbe,
  private val sampleRateHz: Int,
  private val bytesPerFrame: Int,
  private val bytesPerSample: Int = 2,
  private val monotonicTimeNs: () -> Long = System::nanoTime
) {
  private companion object {
    const val PLAYBACK_HEAD_MASK = 0xFFFFFFFFL
    const val NANOSECONDS_PER_SECOND = 1_000_000_000L
  }

  private val pendingFrames = AtomicLong(0)
  private val totalWrittenFrames = AtomicLong(0)
  private var lastRawPlaybackHead = 0L
  private var playbackHeadWraps = 0L
  private var lastReportedPlaybackHead = 0L
  private var estimatedPlaybackHead = 0L
  private var lastEstimateTimeNs = 0L
  private var uncollectedFrames = 0L

  fun markPlaying() {
    lastEstimateTimeNs = monotonicTimeNs()
  }

  fun markPaused() {
    lastEstimateTimeNs = 0L
  }

  fun resetForFlush() {
    pendingFrames.set(0L)
    totalWrittenFrames.set(0L)
    lastRawPlaybackHead = 0L
    playbackHeadWraps = 0L
    lastReportedPlaybackHead = 0L
    estimatedPlaybackHead = 0L
    lastEstimateTimeNs = 0L
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
      playbackHeadWraps += 1L shl 32
    }

    lastRawPlaybackHead = raw
    var absoluteReportedHead = playbackHeadWraps + raw
    val timestampHead = playbackProbe.timestampFramePosition()

    if (timestampHead != null && timestampHead > absoluteReportedHead) {
      absoluteReportedHead = timestampHead
    }

    if (absoluteReportedHead > estimatedPlaybackHead) {
      estimatedPlaybackHead = absoluteReportedHead
    }

    val estimatedHead = estimatePlaybackHead()
    val writtenFrames = totalWrittenFrames.get()
    val absoluteHead = maxOf(absoluteReportedHead, estimatedHead).coerceAtMost(writtenFrames)
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

  private fun estimatePlaybackHead(): Long {
    if (sampleRateHz <= 0) {
      return estimatedPlaybackHead
    }

    if (!playbackProbe.isPlaying()) {
      lastEstimateTimeNs = 0L

      return estimatedPlaybackHead
    }

    val nowNs = monotonicTimeNs()

    if (lastEstimateTimeNs == 0L) {
      lastEstimateTimeNs = nowNs

      return estimatedPlaybackHead
    }

    val elapsedNs = nowNs - lastEstimateTimeNs

    if (elapsedNs <= 0L) {
      return estimatedPlaybackHead
    }

    val advancedFrames = elapsedNs * sampleRateHz / NANOSECONDS_PER_SECOND

    if (advancedFrames <= 0L) {
      return estimatedPlaybackHead
    }

    estimatedPlaybackHead = (estimatedPlaybackHead + advancedFrames).coerceAtMost(totalWrittenFrames.get())
    lastEstimateTimeNs = nowNs

    return estimatedPlaybackHead
  }
}
