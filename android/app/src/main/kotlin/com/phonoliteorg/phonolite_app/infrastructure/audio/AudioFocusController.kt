package com.phonoliteorg.phonolite_app.infrastructure.audio

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
  private val onPauseRequested: () -> Unit,
  private val onResumeRequested: () -> Unit
) {
  // Callbacks arrive on the main looper. Ducking is left to the system (API 26+), so CAN_DUCK only
  // drops ownership; on older releases the stream simply keeps its volume during short prompts.
  private val focusListener =
    AudioManager.OnAudioFocusChangeListener { change ->
      when (change) {
        AudioManager.AUDIOFOCUS_LOSS -> {
          hasFocus = false
          pausedByTransientLoss = false
          onPauseRequested()
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
          hasFocus = false
          pausedByTransientLoss = true
          onPauseRequested()
        }
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> hasFocus = false
        AudioManager.AUDIOFOCUS_GAIN -> {
          hasFocus = true

          if (pausedByTransientLoss) {
            pausedByTransientLoss = false
            onResumeRequested()
          }
        }
      }
    }
  private val noisyReceiver =
    object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
          pausedByTransientLoss = false
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

  // Set only by a transient loss so the matching gain resumes. A user pause during the loss cannot be told
  // apart from the pause this controller requested; a user play re-requests focus and clears it instead.
  @Volatile
  private var pausedByTransientLoss = false

  private val focusRequest: AudioFocusRequest? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(audioAttributes)
        .setOnAudioFocusChangeListener(focusListener)
        .setWillPauseWhenDucked(false)
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
      pausedByTransientLoss = false
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
    pausedByTransientLoss = false
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
