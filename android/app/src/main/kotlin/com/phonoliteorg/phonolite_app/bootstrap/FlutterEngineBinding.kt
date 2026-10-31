package com.phonoliteorg.phonolite_app.bootstrap

import android.os.Handler
import android.os.Looper
import com.phonoliteorg.phonolite_app.application.controllers.media.NativeMediaController
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand
import com.phonoliteorg.phonolite_app.infrastructure.audio.AudioOutputService
import com.phonoliteorg.phonolite_app.infrastructure.flutter.AudioOutputChannelAdapter
import com.phonoliteorg.phonolite_app.infrastructure.flutter.MethodChannelEndpoint
import com.phonoliteorg.phonolite_app.infrastructure.flutter.NowPlayingChannelAdapter
import com.phonoliteorg.phonolite_app.infrastructure.flutter.VehicleChannelAdapter
import com.phonoliteorg.phonolite_app.infrastructure.flutter.VehicleClient
import io.flutter.plugin.common.BinaryMessenger

class FlutterEngineBinding(messenger: BinaryMessenger, media: NativeMediaController, output: AudioOutputService) {
  private val mainHandler = Handler(Looper.getMainLooper())
  private val dispatchToPlatform: (() -> Unit) -> Unit = { operation -> mainHandler.post(operation) }
  private val nowPlaying = NowPlayingChannelAdapter(
    MethodChannelEndpoint(messenger, "phonolite/now_playing"),
    dispatchToPlatform,
    media
  )
  private val vehicle = VehicleChannelAdapter(
    MethodChannelEndpoint(messenger, "phonolite/carplay"),
    dispatchToPlatform,
    media
  )
  private val audio = AudioOutputChannelAdapter(
    MethodChannelEndpoint(messenger, "phonolite/audio_output"),
    dispatchToPlatform,
    output
  )

  val vehicleClient: VehicleClient
    get() = vehicle

  fun attach() {
    nowPlaying.attach()
    vehicle.attach()
    audio.attach()
  }

  fun detach() {
    audio.detach()
    vehicle.detach()
    nowPlaying.detach()
  }

  fun sendRemoteCommand(command: NativeRemoteCommand) {
    nowPlaying.sendRemoteCommand(command)
  }
}
