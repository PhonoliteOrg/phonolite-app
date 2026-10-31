package com.phonoliteorg.phonolite_app.data.models.playback

data class SourceAvailability(
  val serverAvailable: Boolean = false,
  val localAvailable: Boolean = false,
  val hasAnySource: Boolean = false
)
