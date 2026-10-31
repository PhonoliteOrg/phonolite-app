package com.phonoliteorg.phonolite_app.infrastructure.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import com.phonoliteorg.phonolite_app.data.models.audio.AudioOutputConfiguration
import com.phonoliteorg.phonolite_app.data.models.audio.OutputDevice
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class AudioOutputService(context: Context, onPauseRequested: () -> Unit) {
  private val appContext = context.applicationContext
  private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
  private val nextSessionId = AtomicInteger(1)
  private val sessions = ConcurrentHashMap<Int, AudioOutputSession>()
  private val audioAttributes =
    AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_MEDIA)
      .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
      .build()
  private val focusController = AudioFocusController(appContext, audioManager, audioAttributes, onPauseRequested)
  private val deviceCatalog = OutputDeviceCatalog(audioManager)

  fun open(configuration: AudioOutputConfiguration): Int {
    if (configuration.sampleRate <= 0 || configuration.channels !in 1..2) {
      return -1
    }

    focusController.requestFocus()
    focusController.registerNoisyReceiver()

    return try {
      val sessionId = nextSessionId.getAndIncrement()
      val session = AudioOutputSession(audioManager, audioAttributes, configuration)
      sessions[sessionId] = session

      sessionId
    } catch (_: Throwable) {
      releaseFocusIfUnused()

      -1
    }
  }

  fun write(id: Int, pcm: ByteArray): Int {
    val session = sessions[id] ?: return -1

    return session.write(pcm)
  }

  fun setVolume(id: Int, volume: Float): Boolean {
    val session = sessions[id] ?: return false
    session.setVolume(volume)

    return true
  }

  fun flush(id: Int): Boolean {
    val session = sessions[id] ?: return false
    session.flush()

    return true
  }

  fun pause(id: Int): Boolean {
    val session = sessions[id] ?: return false
    session.pause()

    return true
  }

  fun resume(id: Int): Boolean {
    val session = sessions[id] ?: return false
    focusController.requestFocus()
    focusController.registerNoisyReceiver()
    session.resume()

    return true
  }

  fun collectDoneSamples(id: Int): Int {
    val session = sessions[id] ?: return 0

    return session.collectDoneSamples()
  }

  fun isIdle(id: Int): Boolean {
    val session = sessions[id] ?: return true

    return session.isIdle()
  }

  fun close(id: Int): Boolean {
    val session = sessions.remove(id) ?: return false
    session.close()
    releaseFocusIfUnused()

    return true
  }

  fun listOutputDevices(): List<OutputDevice> = deviceCatalog.listOutputDevices()

  private fun releaseFocusIfUnused() {
    if (sessions.isEmpty()) {
      focusController.unregisterNoisyReceiver()
      focusController.abandonFocus()
    }
  }
}
