package com.phonoliteorg.phonolite_app.infrastructure.media

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

class MediaPendingIntents(
  private val context: Context,
  private val activityIntent: () -> Intent,
  private val serviceIntent: () -> Intent
) {
  fun content(): PendingIntent {
    val intent = activityIntent()
    intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    return PendingIntent.getActivity(context, 100, intent, flags)
  }

  fun service(action: String, requestCode: Int): PendingIntent {
    val intent = serviceIntent().setAction(action)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    return PendingIntent.getService(context, requestCode, intent, flags)
  }
}
