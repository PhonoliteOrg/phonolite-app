package com.example.phonolite_app.infrastructure.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.example.phonolite_app.data.models.playback.NativeNowPlayingState

// Foreground transitions and notification registration belong to the service's main-thread lifetime.
class PlaybackNotificationController(
  context: Context,
  private val channelName: String,
  private val channelDescription: String,
  private val createNotification: (NativeNowPlayingState) -> Notification?,
  private val startForeground: (Int, Notification) -> Unit,
  private val stopForeground: (Boolean) -> Unit
) {
  private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  private var isForeground = false

  fun initialize() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }

    val channel = NotificationChannel(
      MediaServiceActions.NOTIFICATION_CHANNEL_ID,
      channelName,
      NotificationManager.IMPORTANCE_LOW
    )
    channel.description = channelDescription
    manager.createNotificationChannel(channel)
  }

  fun destroy() {
    manager.cancel(MediaServiceActions.NOTIFICATION_ID)
  }

  fun publish(state: NativeNowPlayingState): Boolean {
    val notification = createNotification(state)

    if (notification == null) {
      return false
    }

    if (!isForeground) {
      startForeground(MediaServiceActions.NOTIFICATION_ID, notification)
      isForeground = true
    } else {
      manager.notify(MediaServiceActions.NOTIFICATION_ID, notification)
    }

    if (!state.isPlaying) {
      stopForeground(false)
      isForeground = false
      manager.notify(MediaServiceActions.NOTIFICATION_ID, notification)
    }

    return true
  }

  fun clear() {
    manager.cancel(MediaServiceActions.NOTIFICATION_ID)

    if (isForeground) {
      stopForeground(true)
      isForeground = false
    }
  }
}
