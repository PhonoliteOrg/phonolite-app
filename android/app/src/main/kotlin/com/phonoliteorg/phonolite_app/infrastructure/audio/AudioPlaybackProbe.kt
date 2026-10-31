package com.phonoliteorg.phonolite_app.infrastructure.audio

internal interface AudioPlaybackProbe {
  fun playbackHeadPosition(): Long

  fun timestampFramePosition(): Long?

  fun isPlaying(): Boolean
}
