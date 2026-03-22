package com.example.phonolite_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToLong

data class PhonoliteNowPlayingState(
  val epoch: Int,
  val trackId: String,
  val title: String,
  val artist: String,
  val album: String,
  val durationMs: Long,
  val positionMs: Long,
  val isPlaying: Boolean,
  val liked: Boolean,
  val artworkBytes: ByteArray?,
)

data class BridgeInvokeResult(
  val value: Any? = null,
  val error: String? = null,
  val notImplemented: Boolean = false,
)

class PhonolitePlatformBridge(
  context: Context,
  messenger: BinaryMessenger,
) {
  companion object {
    private const val seekBackwardToleranceMs = 750L
  }

  private val appContext = context.applicationContext
  private val mainHandler = Handler(Looper.getMainLooper())
  private val nowPlayingChannel = MethodChannel(messenger, "phonolite/now_playing")
  private val vehicleChannel = MethodChannel(messenger, "phonolite/carplay")
  private val audioOutputChannel = MethodChannel(messenger, "phonolite/audio_output")
  private val audioOutputManager = PhonoliteAudioOutputManager(appContext) { type, args ->
    sendRemoteCommand(type, args)
  }

  @Volatile
  var authorized: Boolean = false
    private set

  private var currentNowPlayingTrackId: String? = null
  private var currentNowPlayingEpoch: Int = 0
  private var lastReportedPositionMs: Long = -1L

  init {
    nowPlayingChannel.setMethodCallHandler(::handleNowPlayingMethod)
    vehicleChannel.setMethodCallHandler(::handleVehicleMethod)
    audioOutputChannel.setMethodCallHandler(audioOutputManager::handleMethodCall)
  }

  fun sendRemoteCommand(
    type: String,
    arguments: Map<String, Any?> = emptyMap(),
  ) {
    val payload = HashMap(arguments)
    payload["type"] = type
    mainHandler.post {
      nowPlayingChannel.invokeMethod("remoteCommand", payload)
    }
  }

  fun invokeVehicleMethod(
    method: String,
    arguments: Any? = null,
    callback: (BridgeInvokeResult) -> Unit,
  ) {
    mainHandler.post {
      vehicleChannel.invokeMethod(
        method,
        arguments,
        object : MethodChannel.Result {
          override fun success(result: Any?) {
            callback(BridgeInvokeResult(value = result))
          }

          override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
          ) {
            callback(
              BridgeInvokeResult(
                error = errorMessage ?: errorCode,
              ),
            )
          }

          override fun notImplemented() {
            callback(BridgeInvokeResult(notImplemented = true))
          }
        },
      )
    }
  }

  private fun handleNowPlayingMethod(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    when (call.method) {
      "setNowPlaying" -> {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        PhonoliteMediaService.publishNowPlaying(
          appContext,
          parseNowPlayingState(args),
        )
        result.success(true)
      }
      "clearNowPlaying" -> {
        resetNowPlayingPositionTracking()
        PhonoliteMediaService.clearNowPlaying(appContext)
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  private fun handleVehicleMethod(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    when (call.method) {
      "authState" -> {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        authorized = args["authorized"] as? Boolean ?: false
        PhonoliteMediaService.updateAuthorization(appContext, authorized)
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  private fun parseNowPlayingState(args: Map<*, *>): PhonoliteNowPlayingState {
    val artworkBytes = when (val artwork = args["artworkBytes"]) {
      is ByteArray -> artwork
      else -> null
    }
    val epoch = (args["epoch"] as? Number)?.toInt() ?: 0
    val trackId = args["trackId"]?.toString().orEmpty()
    return PhonoliteNowPlayingState(
      epoch = epoch,
      trackId = trackId,
      title = args["title"]?.toString().orEmpty(),
      artist = args["artist"]?.toString().orEmpty(),
      album = args["album"]?.toString().orEmpty(),
      durationMs = secondsToMillis(args["duration"]),
      positionMs = applyNowPlayingPosition(
        trackId = trackId,
        epoch = epoch,
        positionMs = secondsToMillis(args["position"]),
      ),
      isPlaying = parseBoolean(args["isPlaying"]),
      liked = parseBoolean(args["liked"]),
      artworkBytes = artworkBytes,
    )
  }

  private fun resetNowPlayingPositionTracking() {
    currentNowPlayingTrackId = null
    currentNowPlayingEpoch = 0
    lastReportedPositionMs = -1L
  }

  private fun applyNowPlayingPosition(
    trackId: String,
    epoch: Int,
    positionMs: Long,
  ): Long {
    val clamped = positionMs.coerceAtLeast(0L)
    if (trackId != currentNowPlayingTrackId) {
      currentNowPlayingTrackId = trackId
      currentNowPlayingEpoch = epoch
      lastReportedPositionMs = -1L
    } else if (epoch != currentNowPlayingEpoch) {
      currentNowPlayingEpoch = epoch
      lastReportedPositionMs = -1L
    }
    if (lastReportedPositionMs < 0L) {
      lastReportedPositionMs = clamped
      return clamped
    }
    if (clamped + seekBackwardToleranceMs < lastReportedPositionMs) {
      return lastReportedPositionMs
    }
    lastReportedPositionMs = clamped
    return clamped
  }

  private fun parseBoolean(value: Any?): Boolean {
    return when (value) {
      is Boolean -> value
      is Number -> value.toInt() != 0
      is String -> value.equals("true", ignoreCase = true) || value == "1"
      else -> false
    }
  }

  private fun secondsToMillis(value: Any?): Long {
    val seconds = when (value) {
      is Number -> value.toDouble()
      is String -> value.toDoubleOrNull()
      else -> null
    } ?: return 0L
    if (!seconds.isFinite()) {
      return 0L
    }
    return (seconds * 1000.0).roundToLong().coerceAtLeast(0L)
  }
}
