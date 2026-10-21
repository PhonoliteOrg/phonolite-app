package com.example.phonolite_app.infrastructure.audio

internal interface AudioPlaybackProbe {
  fun playbackHeadPosition(): Long

  fun timestampFramePosition(): Long?

  fun isPlaying(): Boolean
}
