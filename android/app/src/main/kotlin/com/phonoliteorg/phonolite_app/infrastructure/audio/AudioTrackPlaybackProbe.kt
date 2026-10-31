package com.phonoliteorg.phonolite_app.infrastructure.audio

import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build

internal class AudioTrackPlaybackProbe(private val audioTrack: AudioTrack) : AudioPlaybackProbe {
  private val audioTimestamp =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
      AudioTimestamp()
    } else {
      null
    }

  override fun playbackHeadPosition(): Long = audioTrack.playbackHeadPosition.toLong()

  override fun timestampFramePosition(): Long? {
    val timestamp = audioTimestamp ?: return null

    return runCatching {
      if (audioTrack.getTimestamp(timestamp)) {
        timestamp.framePosition
      } else {
        null
      }
    }.getOrNull()
  }

  override fun isPlaying(): Boolean = audioTrack.playState == AudioTrack.PLAYSTATE_PLAYING
}
