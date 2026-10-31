package com.phonoliteorg.phonolite_app.application.controllers.media

import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState
import com.phonoliteorg.phonolite_app.data.models.playback.PlaybackPositionState
import com.phonoliteorg.phonolite_app.data.models.playback.SourceAvailability

// Dependency-free JVM checks: no Android service, Flutter engine, playback or worker.
object NativeMediaControllerTest {
  @JvmStatic
  fun main(args: Array<String>) {
    backwardToleranceKeepsSmallCorrections()
    newTrackAndEpochResetPositionAcceptance()
    clearResetsSnapshotAndPosition()
    publicationReceivesTheAcceptedSnapshot()
    authorizationPreservesLocalAvailability()
    sourceAvailabilityIncludesEveryAvailableSource()

    println("NativeMediaController: 6 headless JVM checks passed")
  }

  private fun backwardToleranceKeepsSmallCorrections() {
    val position = PlaybackPositionState()
    check(position.apply("track", 1, 10_000L) == 10_000L)
    check(position.apply("track", 1, 9_249L) == 10_000L)
    check(position.apply("track", 1, 9_250L) == 9_250L)
    check(position.apply("track", 1, 12_000L) == 12_000L)
  }

  private fun newTrackAndEpochResetPositionAcceptance() {
    val position = PlaybackPositionState()
    position.apply("track", 1, 10_000L)
    check(position.apply("track", 2, 500L) == 500L)
    check(position.apply("new-track", 2, -200L) == 0L)

    position.apply("new-track", 2, 10_000L)
    position.reset()
    check(position.apply("new-track", 2, 0L) == 0L)
  }

  private fun clearResetsSnapshotAndPosition() {
    var clearCount = 0
    val controller = NativeMediaController({}, { clearCount += 1 }, {})
    controller.publish(snapshot(positionMs = 10_000L))
    controller.clear()
    check(controller.latestState == null)
    check(clearCount == 1)

    controller.publish(snapshot(positionMs = 100L))
    check(controller.latestState?.positionMs == 100L)
  }

  private fun publicationReceivesTheAcceptedSnapshot() {
    val published = mutableListOf<NativeNowPlayingState>()
    val controller = NativeMediaController({ published.add(it) }, {}, {})
    val first = snapshot(positionMs = 10_000L)
    controller.publish(first)
    controller.publish(first.copy(positionMs = 1_000L, title = "New title", liked = true))

    check(published.size == 2)
    check(published.last() === controller.latestState)
    check(published.last().positionMs == 10_000L)
    check(published.last().title == "New title")
    check(published.last().liked)
    check(published.last().artworkBytes === first.artworkBytes)
  }

  private fun authorizationPreservesLocalAvailability() {
    var sourceChanges = 0
    val controller = NativeMediaController({}, {}, { sourceChanges += 1 })
    controller.updateSourceState(serverAvailable = true, localAvailable = true, hasAnySource = true)
    controller.updateAuthorization(false)

    check(!controller.authorized)
    check(controller.availability == SourceAvailability(false, true, true))
    check(sourceChanges == 2)
  }

  private fun sourceAvailabilityIncludesEveryAvailableSource() {
    val controller = NativeMediaController({}, {}, {})
    controller.updateSourceState(serverAvailable = false, localAvailable = true, hasAnySource = false)
    check(controller.availability.hasAnySource)

    controller.updateSourceState(serverAvailable = true, localAvailable = false, hasAnySource = false)
    check(controller.authorized && controller.availability.hasAnySource)

    controller.updateSourceState(serverAvailable = false, localAvailable = false, hasAnySource = true)
    check(controller.availability.hasAnySource)
    controller.updateAuthorization(false)
    check(!controller.availability.hasAnySource)
  }

  private fun snapshot(positionMs: Long): NativeNowPlayingState = NativeNowPlayingState(
    epoch = 1,
    trackId = "track",
    title = "Track",
    artist = "Artist",
    album = "Album",
    durationMs = 90_000L,
    positionMs = positionMs,
    isPlaying = true,
    liked = false,
    artworkBytes = byteArrayOf(1, 2, 3)
  )
}
