package com.example.phonolite_app.infrastructure.audio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

internal class AudioFocusController(
  private val appContext: Context,
  private val audioManager: AudioManager,
  audioAttributes: AudioAttributes,
  private val onPauseRequested: () -> Unit
) {
  private val focusListener =
    AudioManager.OnAudioFocusChangeListener { change ->
      when (change) {
        AudioManager.AUDIOFOCUS_LOSS,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
          hasFocus = false
          onPauseRequested()
        }
        AudioManager.AUDIOFOCUS_GAIN -> hasFocus = true
      }
    }
  private val noisyReceiver =
    object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
          onPauseRequested()
        }
      }
    }

  @Volatile
  private var noisyRegistered = false

  @Volatile
  private var hasFocus = false

  @Volatile
  private var focusRegistered = false

  private val focusRequest: AudioFocusRequest? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(audioAttributes)
        .setOnAudioFocusChangeListener(focusListener)
        .setWillPauseWhenDucked(true)
        .build()
    } else {
      null
    }

  fun requestFocus() {
    if (hasFocus) {
      return
    }

    val granted =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        audioManager.requestAudioFocus(focusRequest!!) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
      } else {
        @Suppress("DEPRECATION")
        audioManager.requestAudioFocus(
          focusListener,
          AudioManager.STREAM_MUSIC,
          AudioManager.AUDIOFOCUS_GAIN
        ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
      }

    if (granted) {
      focusRegistered = true
    }

    hasFocus = granted
  }

  fun abandonFocus() {
    // A transient loss removes ownership while its request remains registered
    // for a later gain. Closing the last session must still abandon it.
    if (!focusRegistered) {
      return
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      audioManager.abandonAudioFocusRequest(focusRequest!!)
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(focusListener)
    }

    focusRegistered = false
    hasFocus = false
  }

  fun registerNoisyReceiver() {
    if (noisyRegistered) {
      return
    }

    appContext.registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    noisyRegistered = true
  }

  fun unregisterNoisyReceiver() {
    if (!noisyRegistered) {
      return
    }

    runCatching {
      appContext.unregisterReceiver(noisyReceiver)
    }
    noisyRegistered = false
  }
}
