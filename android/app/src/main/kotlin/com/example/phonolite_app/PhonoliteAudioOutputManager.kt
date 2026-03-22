package com.example.phonolite_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max

class PhonoliteAudioOutputManager(
  context: Context,
  private val onRemoteCommand: (String, Map<String, Any?>) -> Unit,
) {
  private val appContext = context.applicationContext
  private val audioManager =
    appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
  private val nextSessionId = AtomicInteger(1)
  private val sessions = ConcurrentHashMap<Int, AudioOutputSession>()
  private val audioAttributes =
    AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_MEDIA)
      .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
      .build()
  private val focusListener =
    AudioManager.OnAudioFocusChangeListener { change ->
      when (change) {
        AudioManager.AUDIOFOCUS_LOSS,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
          onRemoteCommand("pause", emptyMap())
        }
      }
    }
  private val noisyReceiver =
    object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
          onRemoteCommand("pause", emptyMap())
        }
      }
    }

  @Volatile
  private var noisyRegistered = false

  @Volatile
  private var hasFocus = false

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

  fun handleMethodCall(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    when (call.method) {
      "open" -> result.success(handleOpen(call.arguments as? Map<*, *>))
      "write" -> result.success(handleWrite(call.arguments as? Map<*, *>))
      "flush" -> result.success(handleFlush(call.arguments as? Map<*, *>))
      "setVolume" -> result.success(handleSetVolume(call.arguments as? Map<*, *>))
      "pause" -> result.success(handlePause(call.arguments as? Map<*, *>))
      "resume" -> result.success(handleResume(call.arguments as? Map<*, *>))
      "collectDoneSamples" -> result.success(handleCollectDoneSamples(call.arguments as? Map<*, *>))
      "isIdle" -> result.success(handleIsIdle(call.arguments as? Map<*, *>))
      "close" -> result.success(handleClose(call.arguments as? Map<*, *>))
      "listOutputDevices" -> result.success(listOutputDevices())
      else -> result.notImplemented()
    }
  }

  private fun handleOpen(args: Map<*, *>?): Int {
    val sampleRate = (args?.get("sampleRate") as? Number)?.toInt() ?: return -1
    val channels = (args["channels"] as? Number)?.toInt() ?: return -1
    val preferredDeviceId = (args["deviceId"] as? Number)?.toInt() ?: -1
    if (sampleRate <= 0 || channels !in 1..2) {
      return -1
    }
    requestAudioFocus()
    registerNoisyReceiver()
    return try {
      val sessionId = nextSessionId.getAndIncrement()
      val session =
        AudioOutputSession(
          audioManager = audioManager,
          audioAttributes = audioAttributes,
          sampleRate = sampleRate,
          channels = channels,
          preferredDeviceId = preferredDeviceId,
        )
      sessions[sessionId] = session
      sessionId
    } catch (_: Throwable) {
      if (sessions.isEmpty()) {
        unregisterNoisyReceiver()
        abandonAudioFocus()
      }
      -1
    }
  }

  private fun handleWrite(args: Map<*, *>?): Int {
    val id = (args?.get("id") as? Number)?.toInt() ?: return -1
    val pcm = args["pcm"] as? ByteArray ?: return -2
    val session = sessions[id] ?: return -1
    return session.write(pcm)
  }

  private fun handleSetVolume(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return false
    val volume = (args["value"] as? Number)?.toFloat() ?: return false
    val session = sessions[id] ?: return false
    session.setVolume(volume)
    return true
  }

  private fun handleFlush(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return false
    val session = sessions[id] ?: return false
    session.flush()
    return true
  }

  private fun handlePause(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return false
    val session = sessions[id] ?: return false
    session.pause()
    return true
  }

  private fun handleResume(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return false
    val session = sessions[id] ?: return false
    requestAudioFocus()
    registerNoisyReceiver()
    session.resume()
    return true
  }

  private fun handleCollectDoneSamples(args: Map<*, *>?): Int {
    val id = (args?.get("id") as? Number)?.toInt() ?: return 0
    val session = sessions[id] ?: return 0
    return session.collectDoneSamples()
  }

  private fun handleIsIdle(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return true
    val session = sessions[id] ?: return true
    return session.isIdle()
  }

  private fun handleClose(args: Map<*, *>?): Boolean {
    val id = (args?.get("id") as? Number)?.toInt() ?: return false
    val session = sessions.remove(id) ?: return false
    session.close()
    if (sessions.isEmpty()) {
      unregisterNoisyReceiver()
      abandonAudioFocus()
    }
    return true
  }

  private fun requestAudioFocus() {
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
          AudioManager.AUDIOFOCUS_GAIN,
        ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
      }
    hasFocus = granted
  }

  private fun abandonAudioFocus() {
    if (!hasFocus) {
      return
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      audioManager.abandonAudioFocusRequest(focusRequest!!)
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(focusListener)
    }
    hasFocus = false
  }

  private fun registerNoisyReceiver() {
    if (noisyRegistered) {
      return
    }
    appContext.registerReceiver(
      noisyReceiver,
      IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
    )
    noisyRegistered = true
  }

  private fun unregisterNoisyReceiver() {
    if (!noisyRegistered) {
      return
    }
    runCatching {
      appContext.unregisterReceiver(noisyReceiver)
    }
    noisyRegistered = false
  }

  private fun listOutputDevices(): List<Map<String, Any>> {
    val devices =
      mutableListOf<Map<String, Any>>(
        mapOf("id" to -1, "name" to "System Default"),
      )
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return devices
    }
    val seenIds = HashSet<Int>()
    audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).forEach { device ->
      if (!seenIds.add(device.id)) {
        return@forEach
      }
      devices.add(
        mapOf(
          "id" to device.id,
          "name" to deviceDisplayName(device),
        ),
      )
    }
    return devices
  }

  private fun deviceDisplayName(device: AudioDeviceInfo): String {
    val label = device.productName?.toString()?.trim().orEmpty()
    if (label.isNotEmpty()) {
      return label
    }
    return when (device.type) {
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth Audio"
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth Headset"
      AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone Earpiece"
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Device Speaker"
      AudioDeviceInfo.TYPE_DOCK -> "Dock"
      AudioDeviceInfo.TYPE_HDMI,
      AudioDeviceInfo.TYPE_HDMI_ARC,
      AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI"
      AudioDeviceInfo.TYPE_LINE_ANALOG,
      AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Line Out"
      AudioDeviceInfo.TYPE_USB_DEVICE,
      AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Audio"
      AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Headphones"
      AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
      else -> "Output ${device.id}"
    }
  }

  private class AudioOutputSession(
    audioManager: AudioManager,
    audioAttributes: AudioAttributes,
    sampleRate: Int,
    channels: Int,
    preferredDeviceId: Int,
  ) {
    private data class QueuedChunk(
      val data: ByteArray,
      val generation: Int,
    )

    private val sampleRateHz = sampleRate
    private val bytesPerFrame = channels * 2
    private val pendingFrames = AtomicLong(0)
    private val totalWrittenFrames = AtomicLong(0)
    private val writeGeneration = AtomicInteger(0)
    private val writeQueue = LinkedBlockingQueue<QueuedChunk>()
    private val audioTrack: AudioTrack
    private val maxBufferedFrames: Long
    private val audioTimestamp =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        AudioTimestamp()
      } else {
        null
      }

    @Volatile
    private var running = true

    private var lastRawPlaybackHead = 0L
    private var playbackHeadWraps = 0L
    private var lastReportedPlaybackHead = 0L
    private var estimatedPlaybackHead = 0L
    private var lastEstimateTimeNs = 0L

    private val writerThread =
      Thread({
        while (running) {
          val chunk =
            try {
              writeQueue.take()
            } catch (_: InterruptedException) {
              break
            }
          if (!running) {
            break
          }
          if (chunk.data.isEmpty()) {
            continue
          }
          if (chunk.generation != writeGeneration.get()) {
            continue
          }
          writeChunk(chunk)
        }
      }, "phonolite-audio-output").apply {
        isDaemon = true
      }

    init {
      val channelMask =
        if (channels == 1) {
          AudioFormat.CHANNEL_OUT_MONO
        } else {
          AudioFormat.CHANNEL_OUT_STEREO
        }
      val minBufferBytes =
        AudioTrack.getMinBufferSize(
          sampleRate,
          channelMask,
          AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(4096)
      val targetBufferBytes = max(minBufferBytes * 2, sampleRate * bytesPerFrame / 4)
      val format =
        AudioFormat.Builder()
          .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
          .setSampleRate(sampleRate)
          .setChannelMask(channelMask)
          .build()
      val builder =
        AudioTrack.Builder()
          .setAudioAttributes(audioAttributes)
          .setAudioFormat(format)
          .setBufferSizeInBytes(targetBufferBytes)
          .setTransferMode(AudioTrack.MODE_STREAM)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
      }
      audioTrack = builder.build()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && preferredDeviceId > 0) {
        val preferredDevice =
          audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { device ->
            device.id == preferredDeviceId
          }
        if (preferredDevice != null) {
          audioTrack.setPreferredDevice(preferredDevice)
        }
      }
      maxBufferedFrames = max(targetBufferBytes / bytesPerFrame, sampleRate).toLong()
      audioTrack.play()
      lastEstimateTimeNs = System.nanoTime()
      writerThread.start()
    }

    fun write(chunk: ByteArray): Int {
      if (!running || chunk.isEmpty()) {
        return -1
      }
      val frames = chunk.size / bytesPerFrame
      if (frames <= 0) {
        return -2
      }
      pollCompletedFrames()
      if (pendingFrames.get() >= maxBufferedFrames * 2) {
        return -3
      }
      pendingFrames.addAndGet(frames.toLong())
      writeQueue.offer(QueuedChunk(chunk, writeGeneration.get()))
      return 0
    }

    fun setVolume(volume: Float) {
      audioTrack.setVolume(volume.coerceIn(0f, 1f))
    }

    fun pause() {
      pollCompletedFrames()
      audioTrack.pause()
      lastEstimateTimeNs = 0L
    }

    fun resume() {
      audioTrack.play()
      lastEstimateTimeNs = System.nanoTime()
    }

    @Synchronized
    fun flush() {
      if (!running) {
        return
      }
      val shouldResume = audioTrack.playState == AudioTrack.PLAYSTATE_PLAYING
      writeGeneration.incrementAndGet()
      writeQueue.clear()
      pendingFrames.set(0L)
      totalWrittenFrames.set(0L)
      lastRawPlaybackHead = 0L
      playbackHeadWraps = 0L
      lastReportedPlaybackHead = 0L
      estimatedPlaybackHead = 0L
      lastEstimateTimeNs = 0L
      runCatching {
        audioTrack.pause()
      }
      runCatching {
        audioTrack.flush()
      }
      if (shouldResume) {
        runCatching {
          audioTrack.play()
        }
        lastEstimateTimeNs = System.nanoTime()
      }
    }

    @Synchronized
    fun collectDoneSamples(): Int {
      val doneFrames = pollCompletedFrames()
      return (doneFrames * bytesPerFrame / 2).toInt()
    }

    @Synchronized
    fun isIdle(): Boolean {
      pollCompletedFrames()
      return pendingFrames.get() <= 0L && writeQueue.isEmpty()
    }

    fun close() {
      running = false
      writeGeneration.incrementAndGet()
      writeQueue.clear()
      writeQueue.offer(QueuedChunk(ByteArray(0), writeGeneration.get()))
      writerThread.interrupt()
      runCatching {
        audioTrack.pause()
      }
      runCatching {
        audioTrack.flush()
      }
      runCatching {
        audioTrack.release()
      }
    }

    private fun writeChunk(chunk: QueuedChunk) {
      var offset = 0
      while (running && offset < chunk.data.size) {
        if (chunk.generation != writeGeneration.get()) {
          break
        }
        val written =
          try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
              audioTrack.write(
                chunk.data,
                offset,
                chunk.data.size - offset,
                AudioTrack.WRITE_BLOCKING,
              )
            } else {
              @Suppress("DEPRECATION")
              audioTrack.write(chunk.data, offset, chunk.data.size - offset)
            }
          } catch (_: Throwable) {
            break
          }
        if (written <= 0) {
          break
        }
        totalWrittenFrames.addAndGet((written / bytesPerFrame).toLong())
        offset += written
      }
    }

    @Synchronized
    private fun pollCompletedFrames(): Long {
      val raw = audioTrack.playbackHeadPosition.toLong() and 0xFFFFFFFFL
      if (raw < lastRawPlaybackHead) {
        playbackHeadWraps += 1L shl 32
      }
      lastRawPlaybackHead = raw
      var absoluteReportedHead = playbackHeadWraps + raw
      val timestamp = audioTimestamp
      if (timestamp != null) {
        val timestampHead =
          runCatching {
            if (audioTrack.getTimestamp(timestamp)) {
              timestamp.framePosition
            } else {
              null
            }
          }.getOrNull()
        if (timestampHead != null && timestampHead > absoluteReportedHead) {
          absoluteReportedHead = timestampHead
        }
      }
      if (absoluteReportedHead > estimatedPlaybackHead) {
        estimatedPlaybackHead = absoluteReportedHead
      }
      val estimatedHead = estimatePlaybackHead()
      val writtenFrames = totalWrittenFrames.get()
      val absoluteHead =
        maxOf(absoluteReportedHead, estimatedHead).coerceAtMost(writtenFrames)
      val deltaFrames = (absoluteHead - lastReportedPlaybackHead).coerceAtLeast(0L)
      if (deltaFrames > 0L) {
        lastReportedPlaybackHead = absoluteHead
        pendingFrames.updateAndGet { current ->
          if (current <= deltaFrames) {
            0L
          } else {
            current - deltaFrames
          }
        }
      }
      return deltaFrames
    }

    private fun estimatePlaybackHead(): Long {
      if (sampleRateHz <= 0) {
        return estimatedPlaybackHead
      }
      if (audioTrack.playState != AudioTrack.PLAYSTATE_PLAYING) {
        lastEstimateTimeNs = 0L
        return estimatedPlaybackHead
      }

      val nowNs = System.nanoTime()
      if (lastEstimateTimeNs == 0L) {
        lastEstimateTimeNs = nowNs
        return estimatedPlaybackHead
      }

      val elapsedNs = nowNs - lastEstimateTimeNs
      if (elapsedNs <= 0L) {
        return estimatedPlaybackHead
      }

      val advancedFrames = elapsedNs * sampleRateHz / 1_000_000_000L
      if (advancedFrames <= 0L) {
        return estimatedPlaybackHead
      }

      estimatedPlaybackHead =
        (estimatedPlaybackHead + advancedFrames).coerceAtMost(totalWrittenFrames.get())
      lastEstimateTimeNs = nowNs
      return estimatedPlaybackHead
    }
  }
}
