package com.phonoliteorg.phonolite_app.data.models.playback

// Artwork bytes are borrowed from the channel snapshot and are never mutated by native presentation.
// Snapshot equality retains the array's identity; publication never depends on image-byte equality.
data class NativeNowPlayingState(
  val epoch: Int,
  val trackId: String,
  val title: String,
  val artist: String,
  val album: String,
  val durationMs: Long,
  val positionMs: Long,
  val isPlaying: Boolean,
  val liked: Boolean,
  val artworkBytes: ByteArray?
)
