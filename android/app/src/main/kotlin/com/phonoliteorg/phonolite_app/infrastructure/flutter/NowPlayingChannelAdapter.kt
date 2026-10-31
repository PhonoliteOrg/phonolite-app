package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.application.controllers.media.NativeMediaController
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NowPlayingChannelAdapter(
  endpoint: FlutterChannelEndpoint,
  dispatchToPlatform: (() -> Unit) -> Unit,
  private val media: NativeMediaController,
  private val codec: NowPlayingCodec = NowPlayingCodec()
) : FlutterChannelAdapter(endpoint, dispatchToPlatform) {
  fun sendRemoteCommand(command: NativeRemoteCommand) {
    invoke("remoteCommand", codec.encode(command))
  }

  override fun handleCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "setNowPlaying" -> {
        media.publish(codec.decode(call.arguments))
        result.success(true)
      }
      "clearNowPlaying" -> {
        media.clear()
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }
}
