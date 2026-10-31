package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.infrastructure.audio.AudioOutputService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioOutputChannelAdapter(
  endpoint: FlutterChannelEndpoint,
  dispatchToPlatform: (() -> Unit) -> Unit,
  private val output: AudioOutputService,
  private val codec: AudioOutputCodec = AudioOutputCodec()
) : FlutterChannelAdapter(endpoint, dispatchToPlatform) {
  override fun handleCall(call: MethodCall, result: MethodChannel.Result) {
    val values = call.arguments as? Map<*, *>
    val id = codec.id(values)
    val response: Any = when (call.method) {
      "open" -> codec.configuration(values)?.let(output::open) ?: -1
      "write" -> write(id, values)
      "setVolume" -> setVolume(id, values)
      "flush" -> id?.let(output::flush) ?: false
      "pause" -> id?.let(output::pause) ?: false
      "resume" -> id?.let(output::resume) ?: false
      "collectDoneSamples" -> id?.let(output::collectDoneSamples) ?: 0
      "isIdle" -> id?.let(output::isIdle) ?: true
      "close" -> id?.let(output::close) ?: false
      "listOutputDevices" -> codec.encodeDevices(output.listOutputDevices())
      else -> {
        result.notImplemented()

        return
      }
    }

    result.success(response)
  }

  private fun write(id: Int?, values: Map<*, *>?): Int {
    if (id == null) {
      return -1
    }

    val pcm = values?.get("pcm") as? ByteArray ?: return -2

    return output.write(id, pcm)
  }

  private fun setVolume(id: Int?, values: Map<*, *>?): Boolean {
    if (id == null) {
      return false
    }

    val volume = (values?.get("value") as? Number)?.toFloat() ?: return false

    return output.setVolume(id, volume)
  }
}
