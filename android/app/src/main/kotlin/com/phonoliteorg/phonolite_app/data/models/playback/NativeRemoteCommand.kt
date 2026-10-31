package com.phonoliteorg.phonolite_app.data.models.playback

sealed interface NativeRemoteCommand {
  data object Play : NativeRemoteCommand
  data object Pause : NativeRemoteCommand
  data object Next : NativeRemoteCommand
  data object Previous : NativeRemoteCommand
  data object ToggleLike : NativeRemoteCommand
  data class Seek(val positionSeconds: Double) : NativeRemoteCommand
}
