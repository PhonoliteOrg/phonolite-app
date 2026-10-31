package com.phonoliteorg.phonolite_app.data.models.playback

class PlaybackPositionState {
  companion object {
    private const val SEEK_BACKWARD_TOLERANCE_MS = 750L
  }

  private var currentTrackId: String? = null
  private var currentEpoch = 0
  private var lastPositionMs = -1L

  fun reset() {
    currentTrackId = null
    currentEpoch = 0
    lastPositionMs = -1L
  }

  fun apply(trackId: String, epoch: Int, positionMs: Long): Long {
    val clamped = positionMs.coerceAtLeast(0L)

    if (trackId != currentTrackId) {
      currentTrackId = trackId
      currentEpoch = epoch
      lastPositionMs = -1L
    } else if (epoch != currentEpoch) {
      currentEpoch = epoch
      lastPositionMs = -1L
    }

    if (lastPositionMs < 0L) {
      lastPositionMs = clamped
      return clamped
    }

    if (clamped + SEEK_BACKWARD_TOLERANCE_MS < lastPositionMs) {
      return lastPositionMs
    }

    lastPositionMs = clamped

    return clamped
  }
}
