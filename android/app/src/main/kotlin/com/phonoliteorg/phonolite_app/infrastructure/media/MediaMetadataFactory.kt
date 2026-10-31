package com.phonoliteorg.phonolite_app.infrastructure.media

import android.support.v4.media.MediaMetadataCompat
import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState

class MediaMetadataFactory(private val artwork: ArtworkDecoder) {
  fun build(state: NativeNowPlayingState?): MediaMetadataCompat? {
    if (state == null || state.trackId.isBlank()) {
      return null
    }

    val builder = MediaMetadataCompat.Builder()
      .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, state.trackId)
      .putString(MediaMetadataCompat.METADATA_KEY_TITLE, state.title)
      .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, state.artist)
      .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, state.album)
      .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, state.durationMs)

    artwork.decode(state.artworkBytes)?.let { bitmap ->
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bitmap)
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, bitmap)
    }

    return builder.build()
  }
}
