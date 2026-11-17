package com.phonoliteorg.phonolite_app.infrastructure.media

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.ServiceCompat
import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState

// Foreground transitions and notification registration belong to the service's main-thread lifetime.
class PlaybackNotificationController(
  context: Context,
  private val channelName: String,
  private val channelDescription: String,
  private val createNotification: (NativeNowPlayingState) -> Notification?,
  private val createPlaceholder: () -> Notification,
  private val startForeground: (Int, Notification) -> Unit,
  private val stopForeground: (Int) -> Unit
) {
  companion object {
    private const val TAG = "PlaybackNotifications"
  }

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

  /**
   * Satisfies a `startForegroundService` start, which must reach `startForeground` within seconds even when
   * there is nothing to show. A later [publish] or [clear] replaces or removes the placeholder.
   */
  fun fulfillForegroundStart(state: NativeNowPlayingState?) {
    if (isForeground) {
      return
    }

    val notification = state?.let(createNotification) ?: createPlaceholder()
    enterForeground(notification)
  }

  fun publish(state: NativeNowPlayingState): Boolean {
    val notification = createNotification(state)

    if (notification == null) {
      return false
    }

    if (!state.isPlaying) {
      if (isForeground) {
        stopForeground(ServiceCompat.STOP_FOREGROUND_DETACH)
        isForeground = false
      }

      manager.notify(MediaServiceActions.NOTIFICATION_ID, notification)
      return true
    }

    if (isForeground) {
      manager.notify(MediaServiceActions.NOTIFICATION_ID, notification)
    } else {
      enterForeground(notification)
    }

    return true
  }

  fun clear() {
    if (isForeground) {
      stopForeground(ServiceCompat.STOP_FOREGROUND_REMOVE)
      isForeground = false
    }

    manager.cancel(MediaServiceActions.NOTIFICATION_ID)
  }

  private fun enterForeground(notification: Notification) {
    try {
      startForeground(MediaServiceActions.NOTIFICATION_ID, notification)
      isForeground = true
    } catch (error: IllegalStateException) {
      // Android 12+ refuses to re-enter the foreground from the background, e.g. resuming after a pause
      // detached the service. Playback continues; the notification stays visible without foreground status.
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || error !is ForegroundServiceStartNotAllowedException) {
        throw error
      }

      Log.w(TAG, "Foreground restart not allowed; posting the playback notification only", error)
      manager.notify(MediaServiceActions.NOTIFICATION_ID, notification)
    }
  }
}
