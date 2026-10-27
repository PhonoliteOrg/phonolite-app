package com.example.phonolite_app.infrastructure.audio

// Dependency-free JVM checks: no AudioTrack, Android runtime, playback or worker.
object AudioPlaybackProgressTest {
  @JvmStatic
  fun main(args: Array<String>) {
    completedFramesAreCollectedExactlyOnce()
    timestampProgressDoesNotRegress()
    estimatedProgressCannotExceedWrittenAudio()
    pausedTimeDoesNotAdvanceProgress()
    flushPreservesUncollectedCompletions()
    unsignedPlaybackHeadWrapsWithoutLosingFrames()
    rejectedWriteAccountingCannotBecomeNegative()
    originalPcm32CountsSamplesIndependentlyOfPrecision()

    println("AudioPlaybackProgress: 8 headless JVM checks passed")
  }

  private fun completedFramesAreCollectedExactlyOnce() {
    val fixture = Fixture()
    fixture.addFrames(100)
    fixture.probe.rawHead = 20L
    check(fixture.progress.pollCompletedFrames() == 20L)

    fixture.probe.rawHead = 25L
    fixture.probe.timestampHead = 30L
    check(fixture.progress.pollCompletedFrames() == 10L)
    check(fixture.progress.pendingFrameCount() == 70L)
    check(fixture.progress.collectDoneSamples() == 60)
    check(fixture.progress.collectDoneSamples() == 0)
  }

  private fun timestampProgressDoesNotRegress() {
    val fixture = Fixture()
    fixture.addFrames(200)
    fixture.probe.rawHead = 50L
    fixture.probe.timestampHead = 100L
    check(fixture.progress.collectDoneSamples() == 200)

    fixture.probe.rawHead = 60L
    fixture.probe.timestampHead = 80L
    check(fixture.progress.collectDoneSamples() == 0)
    check(fixture.progress.pendingFrameCount() == 100L)
  }

  private fun estimatedProgressCannotExceedWrittenAudio() {
    val fixture = Fixture()
    fixture.addFrames(480)
    fixture.probe.playing = true
    fixture.progress.markPlaying()
    fixture.timeNs += 20_000_000L

    check(fixture.progress.collectDoneSamples() == 960)
    check(fixture.progress.pendingFrameCount() == 0L)

    fixture.timeNs += 20_000_000L
    check(fixture.progress.collectDoneSamples() == 0)
  }

  private fun pausedTimeDoesNotAdvanceProgress() {
    val fixture = Fixture()
    fixture.addFrames(480)
    fixture.progress.markPlaying()
    fixture.timeNs += 2_000_000_000L
    check(fixture.progress.collectDoneSamples() == 0)

    fixture.probe.playing = true
    fixture.progress.markPlaying()
    fixture.timeNs += 5_000_000L
    check(fixture.progress.collectDoneSamples() == 480)

    fixture.probe.playing = false
    fixture.progress.markPaused()
    fixture.timeNs += 2_000_000_000L
    check(fixture.progress.collectDoneSamples() == 0)
    check(fixture.progress.pendingFrameCount() == 240L)
  }

  private fun flushPreservesUncollectedCompletions() {
    val fixture = Fixture()
    fixture.addFrames(100)
    fixture.probe.rawHead = 20L
    check(fixture.progress.pollCompletedFrames() == 20L)

    fixture.progress.resetForFlush()
    fixture.probe.rawHead = 0L
    fixture.addFrames(40)
    check(fixture.progress.collectDoneSamples() == 40)

    fixture.probe.rawHead = 10L
    check(fixture.progress.collectDoneSamples() == 20)
    check(fixture.progress.pendingFrameCount() == 30L)
  }

  private fun unsignedPlaybackHeadWrapsWithoutLosingFrames() {
    val fixture = Fixture()
    repeat(10) {
      fixture.progress.addPendingFrames(500_000_000L)
      fixture.progress.recordWrittenBytes(2_000_000_000)
    }
    fixture.probe.rawHead = -16L
    check(fixture.progress.pollCompletedFrames() == 0xFFFF_FFF0L)
    check(fixture.progress.collectDoneSamples() == 2_147_483_646)

    fixture.probe.rawHead = 16L
    check(fixture.progress.pollCompletedFrames() == 32L)
    check(fixture.progress.pendingFrameCount() == 5_000_000_000L - (1L shl 32) - 16L)
  }

  private fun rejectedWriteAccountingCannotBecomeNegative() {
    val fixture = Fixture()
    fixture.progress.addPendingFrames(100L)
    fixture.progress.addPendingFrames(-10L)
    fixture.progress.discardPendingFrames(25)
    check(fixture.progress.pendingFrameCount() == 65L)

    fixture.progress.discardPendingFrames(1000)
    check(fixture.progress.pendingFrameCount() == 0L)
  }

  private fun originalPcm32CountsSamplesIndependentlyOfPrecision() {
    val fixture = Fixture(bytesPerSample = 4)
    fixture.addFrames(1920)
    fixture.probe.rawHead = 960

    check(fixture.progress.collectDoneSamples() == 1920)
    check(fixture.progress.pendingFrameCount() == 960L)
    check(fixture.progress.collectDoneSamples() == 0)
  }

  private class Fixture(private val bytesPerSample: Int = 2) {
    val probe = Probe()
    var timeNs = 1_000_000_000L
    val progress = AudioPlaybackProgress(probe, 48_000, 2 * bytesPerSample, bytesPerSample) { timeNs }

    fun addFrames(frames: Int) {
      progress.addPendingFrames(frames.toLong())
      progress.recordWrittenBytes(frames * 2 * bytesPerSample)
    }
  }

  private class Probe : AudioPlaybackProbe {
    var rawHead = 0L
    var timestampHead: Long? = null
    var playing = false

    override fun playbackHeadPosition(): Long = rawHead

    override fun timestampFramePosition(): Long? = timestampHead

    override fun isPlaying(): Boolean = playing
  }
}
