package com.example.phonolite_app.infrastructure.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import com.example.phonolite_app.data.models.audio.AudioOutputConfiguration
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

internal class AudioOutputSession(
  audioManager: AudioManager,
  audioAttributes: AudioAttributes,
  configuration: AudioOutputConfiguration
) {
  private companion object {
    const val MAX_QUEUED_CHUNKS = 5
    const val MIN_BUFFER_BYTES = 4096
    const val WRITE_RETRY_DELAY_MS = 2L
  }

  private data class QueuedChunk(val data: ByteArray, val generation: Int)

  private val encoding = encodingFor(configuration)
  private val bytesPerSample = configuration.bitsPerSample / 8
  private val bytesPerFrame = configuration.channels * bytesPerSample
  private val writeGeneration = AtomicInteger(0)
  private val writeQueue = LinkedBlockingQueue<QueuedChunk>(MAX_QUEUED_CHUNKS)
  private val writeLock = Any()
  private val writeFailure = AtomicInteger(0)
  private val audioTrack: AudioTrack
  private val maxBufferedFrames: Long
  private val progress: AudioPlaybackProgress

  @Volatile
  private var running = true

  private val writerThread =
    Thread(::processWriteQueue, "phonolite-audio-output").apply {
      isDaemon = true
    }

  init {
    val channelMask =
      if (configuration.channels == 1) {
        AudioFormat.CHANNEL_OUT_MONO
      } else {
        AudioFormat.CHANNEL_OUT_STEREO
      }
    val minBufferBytes =
      AudioTrack.getMinBufferSize(
        configuration.sampleRate,
        channelMask,
        encoding
      ).coerceAtLeast(MIN_BUFFER_BYTES)
    val targetBufferBytes = max(minBufferBytes, configuration.sampleRate * bytesPerFrame / 10)
    val format =
      AudioFormat.Builder()
        .setEncoding(encoding)
        .setSampleRate(configuration.sampleRate)
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

    if (audioTrack.state != AudioTrack.STATE_INITIALIZED) {
      audioTrack.release()
      throw IllegalArgumentException("The audio device does not support the original PCM format")
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && configuration.deviceId > 0) {
      val preferredDevice =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { device ->
          device.id == configuration.deviceId
        }

      if (preferredDevice != null) {
        audioTrack.setPreferredDevice(preferredDevice)
      }
    }

    maxBufferedFrames = max(targetBufferBytes / bytesPerFrame, configuration.sampleRate / 5).toLong()
    progress =
      AudioPlaybackProgress(AudioTrackPlaybackProbe(audioTrack), configuration.sampleRate, bytesPerFrame, bytesPerSample)
    audioTrack.play()
    progress.markPlaying()
    writerThread.start()
  }

  @Synchronized
  fun close() {
    synchronized(writeLock) {
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
  }

  @Synchronized
  fun write(chunk: ByteArray): Int {
    if (!running || chunk.isEmpty()) {
      return -1
    }

    val frames = chunk.size / bytesPerFrame

    if (frames <= 0 || chunk.size % bytesPerFrame != 0) {
      return -2
    }

    val failure = writeFailure.get()

    if (failure != 0) {
      return failure
    }

    progress.pollCompletedFrames()

    synchronized(writeLock) {
      if (progress.pendingFrameCount() + frames > maxBufferedFrames) {
        return -3
      }

      progress.addPendingFrames(frames.toLong())

      if (!writeQueue.offer(QueuedChunk(chunk, writeGeneration.get()))) {
        progress.addPendingFrames(-frames.toLong())

        return -3
      }

      return 0
    }
  }

  fun setVolume(volume: Float) {
    audioTrack.setVolume(volume.coerceIn(0f, 1f))
  }

  @Synchronized
  fun pause() {
    progress.pollCompletedFrames()

    synchronized(writeLock) {
      audioTrack.pause()
      progress.markPaused()
    }
  }

  @Synchronized
  fun resume() {
    synchronized(writeLock) {
      audioTrack.play()
      progress.markPlaying()
    }
  }

  @Synchronized
  fun flush() {
    if (!running) {
      return
    }

    synchronized(writeLock) {
      val shouldResume = audioTrack.playState == AudioTrack.PLAYSTATE_PLAYING
      writeGeneration.incrementAndGet()
      writeQueue.clear()
      progress.resetForFlush()
      writeFailure.set(0)

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
        progress.markPlaying()
      }
    }
  }

  @Synchronized
  fun collectDoneSamples(): Int = progress.collectDoneSamples()

  @Synchronized
  fun isIdle(): Boolean {
    progress.pollCompletedFrames()

    return progress.pendingFrameCount() <= 0L && writeQueue.isEmpty()
  }

  private fun processWriteQueue() {
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
  }

  private fun writeChunk(chunk: QueuedChunk) {
    var offset = 0
    val pcm =
      if (bytesPerSample == 4) {
        val buffer = ByteBuffer.allocateDirect(chunk.data.size).order(ByteOrder.nativeOrder())

        if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
          val source = ByteBuffer.wrap(chunk.data).order(ByteOrder.nativeOrder())

          while (source.hasRemaining()) {
            buffer.putFloat((source.int.toDouble() / 2147483648.0).toFloat())
          }
        } else {
          buffer.put(chunk.data)
        }

        buffer.flip()
        buffer
      } else {
        null
      }

    while (running && offset < chunk.data.size) {
      val written =
        synchronized(writeLock) {
          if (!running || chunk.generation != writeGeneration.get()) {
            return
          }

          // The nonblocking call lets pause and seek acquire this lock even
          // when the device has no buffer space. The builder requires API 23.
          val accepted =
            try {
              if (pcm != null) {
                audioTrack.write(pcm, pcm.remaining(), AudioTrack.WRITE_NON_BLOCKING)
              } else {
                audioTrack.write(chunk.data, offset, chunk.data.size - offset, AudioTrack.WRITE_NON_BLOCKING)
              }
            } catch (_: Throwable) {
              -1
            }

          if (accepted > 0) {
            // Reset and generation changes use this same lock, preventing an
            // obsolete write from advancing the new generation's ledger.
            progress.recordWrittenBytes(accepted)
          } else if (accepted < 0) {
            writeFailure.set(accepted)
            val remainingFrames = (chunk.data.size - offset) / bytesPerFrame
            progress.discardPendingFrames(remainingFrames)
          }

          accepted
        }

      if (written < 0) {
        break
      }

      if (written == 0) {
        try {
          Thread.sleep(WRITE_RETRY_DELAY_MS)
        } catch (_: InterruptedException) {
          return
        }

        continue
      }

      offset += written
    }
  }

  private fun encodingFor(configuration: AudioOutputConfiguration): Int {
    require(configuration.sampleRate > 0 && configuration.channels in 1..2) { "Unsupported PCM layout" }
    require(configuration.bitsPerSample == 16 || configuration.bitsPerSample == 32) { "Unsupported PCM container" }
    require(configuration.validBitsPerSample in 1..configuration.bitsPerSample) { "Invalid PCM precision" }

    if (configuration.bitsPerSample == 16) {
      return AudioFormat.ENCODING_PCM_16BIT
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return AudioFormat.ENCODING_PCM_32BIT
    }

    // Every signed 24-bit integer is exactly representable in float PCM. True
    // 32-bit sources must not silently lose their low bits on older devices.
    require(configuration.validBitsPerSample <= 24) { "Original 32-bit PCM requires Android 12 or newer" }

    return AudioFormat.ENCODING_PCM_FLOAT
  }
}
