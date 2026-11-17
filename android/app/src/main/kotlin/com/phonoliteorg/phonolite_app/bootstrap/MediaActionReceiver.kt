package com.phonoliteorg.phonolite_app.bootstrap

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaServiceActions

// Non-exported target of the notification's transport actions; only this app's PendingIntents can reach it.
class MediaActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val command = when (intent.action) {
      MediaServiceActions.PLAY -> NativeRemoteCommand.Play
      MediaServiceActions.PAUSE -> NativeRemoteCommand.Pause
      MediaServiceActions.NEXT -> NativeRemoteCommand.Next
      MediaServiceActions.PREVIOUS -> NativeRemoteCommand.Previous
      MediaServiceActions.TOGGLE_LIKE -> NativeRemoteCommand.ToggleLike
      else -> return
    }

    val host = (context.applicationContext as PhonoliteApplication).nativeHost
    host.sendRemoteCommand(command)
  }
}
