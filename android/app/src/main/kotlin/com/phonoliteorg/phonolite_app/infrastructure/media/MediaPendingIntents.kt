package com.phonoliteorg.phonolite_app.infrastructure.media

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

class MediaPendingIntents(
  private val context: Context,
  private val activityIntent: () -> Intent,
  private val actionIntent: () -> Intent
) {
  fun content(): PendingIntent {
    val intent = activityIntent()
    intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    return PendingIntent.getActivity(context, 100, intent, flags)
  }

  // Transport actions target a non-exported receiver so other apps cannot send them.
  fun action(action: String, requestCode: Int): PendingIntent {
    val intent = actionIntent().setAction(action)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    return PendingIntent.getBroadcast(context, requestCode, intent, flags)
  }
}
