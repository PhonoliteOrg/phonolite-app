package com.example.phonolite_app.ui.media

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.graphics.Bitmap
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import com.example.phonolite_app.R
import com.example.phonolite_app.data.models.playback.NativeNowPlayingState
import com.example.phonolite_app.infrastructure.media.MediaServiceActions

class PlaybackNotificationFactory(
  private val context: Context,
  private val contentIntent: () -> PendingIntent,
  private val serviceIntent: (String, Int) -> PendingIntent,
  private val decodeArtwork: (ByteArray?) -> Bitmap?
) {
  val channelName = "Phonolite playback"
  val channelDescription = "Playback controls and now playing updates"

  fun likeAction(liked: Boolean): PlaybackStateCompat.CustomAction = PlaybackStateCompat.CustomAction.Builder(
    MediaServiceActions.TOGGLE_LIKE,
    if (liked) "Unlike" else "Like",
    if (liked) R.drawable.ic_lucide_star_selected else R.drawable.ic_lucide_star
  ).build()

  private fun action(icon: Int, title: String, action: String): NotificationCompat.Action =
    NotificationCompat.Action.Builder(icon, title, serviceIntent(action, action.hashCode())).build()

  private fun playPauseAction(isPlaying: Boolean): NotificationCompat.Action {
    if (isPlaying) {
      return action(R.drawable.ic_lucide_pause, "Pause", MediaServiceActions.PAUSE)
    }

    return action(R.drawable.ic_lucide_play, "Play", MediaServiceActions.PLAY)
  }

  fun build(state: NativeNowPlayingState, sessionToken: MediaSessionCompat.Token): Notification? {
    if (state.trackId.isBlank()) {
      return null
    }

    val subtitle = listOf(state.artist, state.album)
      .filter { it.isNotBlank() }
      .joinToString(" - ")
      .ifBlank { "Now Playing" }
    val style = MediaStyle()
      .setMediaSession(sessionToken)
      .setShowActionsInCompactView(0, 1, 2)
    val builder = NotificationCompat.Builder(context, MediaServiceActions.NOTIFICATION_CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_lucide_audio_lines)
      .setContentTitle(if (state.title.isBlank()) "Phonolite" else state.title)
      .setContentText(subtitle)
      .setContentIntent(contentIntent())
      .setDeleteIntent(serviceIntent(MediaServiceActions.PAUSE, 10))
      .setOnlyAlertOnce(true)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
      .setOngoing(state.isPlaying)
      .setShowWhen(false)
      .setStyle(style)
      .addAction(action(R.drawable.ic_lucide_skip_back, "Previous", MediaServiceActions.PREVIOUS))
      .addAction(playPauseAction(state.isPlaying))
      .addAction(action(R.drawable.ic_lucide_skip_forward, "Next", MediaServiceActions.NEXT))
      .addAction(
        action(
          if (state.liked) R.drawable.ic_lucide_star_selected else R.drawable.ic_lucide_star,
          if (state.liked) "Unlike" else "Like",
          MediaServiceActions.TOGGLE_LIKE
        )
      )

    decodeArtwork(state.artworkBytes)?.let { bitmap -> builder.setLargeIcon(bitmap) }

    return builder.build()
  }
}
