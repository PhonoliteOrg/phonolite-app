package com.phonoliteorg.phonolite_app.application.controllers.media

import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState
import com.phonoliteorg.phonolite_app.data.models.playback.PlaybackPositionState
import com.phonoliteorg.phonolite_app.data.models.playback.SourceAvailability

// Process state is published on Android's platform main thread; observations retain volatile visibility.
class NativeMediaController(
  private val onPublish: (NativeNowPlayingState) -> Unit,
  private val onClear: () -> Unit,
  private val onSourcesChanged: () -> Unit
) {
  private val position = PlaybackPositionState()

  @Volatile
  var latestState: NativeNowPlayingState? = null
    private set

  @Volatile
  var availability = SourceAvailability()
    private set

  val authorized: Boolean
    get() = availability.serverAvailable

  fun publish(state: NativeNowPlayingState) {
    val accepted = state.copy(positionMs = position.apply(state.trackId, state.epoch, state.positionMs))
    latestState = accepted

    onPublish(accepted)
  }

  fun clear() {
    position.reset()
    latestState = null

    onClear()
  }

  fun updateAuthorization(isAuthorized: Boolean) {
    availability = availability.copy(
      serverAvailable = isAuthorized,
      hasAnySource = isAuthorized || availability.localAvailable
    )

    onSourcesChanged()
  }

  fun updateSourceState(serverAvailable: Boolean, localAvailable: Boolean, hasAnySource: Boolean) {
    availability = SourceAvailability(
      serverAvailable = serverAvailable,
      localAvailable = localAvailable,
      hasAnySource = hasAnySource || serverAvailable || localAvailable
    )

    onSourcesChanged()
  }
}
