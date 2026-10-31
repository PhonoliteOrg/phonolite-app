package com.phonoliteorg.phonolite_app.infrastructure.media

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState

// Platform-main-thread service registration; the process owner never strongly retains the Android service.
class MediaServiceGateway(context: Context, private val serviceIntent: () -> Intent) {
  private val appContext = context.applicationContext
  private val connection = MediaServiceConnection(
    startService = {
      val intent = serviceIntent().setAction(MediaServiceActions.SYNC_STATE)
      ContextCompat.startForegroundService(appContext, intent)
    },
    stopService = { appContext.stopService(serviceIntent()) }
  )

  fun attach(observer: MediaServiceObserver) {
    connection.attach(observer)
  }

  fun markStarted(observer: MediaServiceObserver) {
    connection.markStarted(observer)
  }

  fun detach(observer: MediaServiceObserver) {
    connection.detach(observer)
  }

  fun publish(@Suppress("UNUSED_PARAMETER") state: NativeNowPlayingState) {
    connection.publish()
  }

  fun clear() {
    connection.clear()
  }

  fun sourcesChanged() {
    connection.sourcesChanged()
  }
}
