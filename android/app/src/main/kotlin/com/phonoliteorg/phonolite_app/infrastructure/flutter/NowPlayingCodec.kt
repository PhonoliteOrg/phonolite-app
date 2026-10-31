package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand
import kotlin.math.roundToLong

class NowPlayingCodec {
  fun decode(arguments: Any?): NativeNowPlayingState {
    val values = arguments as? Map<*, *> ?: emptyMap<String, Any?>()

    return NativeNowPlayingState(
      epoch = (values["epoch"] as? Number)?.toInt() ?: 0,
      trackId = values["trackId"]?.toString().orEmpty(),
      title = values["title"]?.toString().orEmpty(),
      artist = values["artist"]?.toString().orEmpty(),
      album = values["album"]?.toString().orEmpty(),
      durationMs = secondsToMillis(values["duration"]),
      positionMs = secondsToMillis(values["position"]),
      isPlaying = parseBoolean(values["isPlaying"]),
      liked = parseBoolean(values["liked"]),
      artworkBytes = values["artworkBytes"] as? ByteArray
    )
  }

  fun encode(command: NativeRemoteCommand): Map<String, Any?> = when (command) {
    NativeRemoteCommand.Play -> mapOf("type" to "play")
    NativeRemoteCommand.Pause -> mapOf("type" to "pause")
    NativeRemoteCommand.Next -> mapOf("type" to "next")
    NativeRemoteCommand.Previous -> mapOf("type" to "prev")
    NativeRemoteCommand.ToggleLike -> mapOf("type" to "toggleLike")
    is NativeRemoteCommand.Seek -> mapOf("type" to "seek", "position" to command.positionSeconds)
  }

  private fun parseBoolean(value: Any?): Boolean = when (value) {
    is Boolean -> value
    is Number -> value.toInt() != 0
    is String -> value.equals("true", ignoreCase = true) || value == "1"
    else -> false
  }

  private fun secondsToMillis(value: Any?): Long {
    val seconds = when (value) {
      is Number -> value.toDouble()
      is String -> value.toDoubleOrNull()
      else -> null
    } ?: return 0L

    if (!seconds.isFinite()) {
      return 0L
    }

    return (seconds * 1000.0).roundToLong().coerceAtLeast(0L)
  }
}
