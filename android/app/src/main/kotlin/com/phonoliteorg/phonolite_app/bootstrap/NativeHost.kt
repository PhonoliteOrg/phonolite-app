package com.phonoliteorg.phonolite_app.bootstrap

import android.content.Context
import android.content.Intent
import com.phonoliteorg.phonolite_app.application.controllers.media.NativeMediaController
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand
import com.phonoliteorg.phonolite_app.infrastructure.audio.AudioOutputService
import com.phonoliteorg.phonolite_app.infrastructure.flutter.VehicleClient
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaServiceGateway
import io.flutter.embedding.engine.FlutterEngine

class NativeHost(context: Context) {
  private val appContext = context.applicationContext
  val mediaServiceGateway = MediaServiceGateway(appContext) { Intent(appContext, PhonoliteMediaService::class.java) }
  val mediaController = NativeMediaController(
    mediaServiceGateway::publish,
    mediaServiceGateway::clear,
    mediaServiceGateway::sourcesChanged
  )
  private val audioOutput by lazy {
    AudioOutputService(appContext) { sendRemoteCommand(NativeRemoteCommand.Pause) }
  }
  private val engineOwner = FlutterEngineOwner(appContext) { messenger ->
    FlutterEngineBinding(messenger, mediaController, audioOutput)
  }

  val vehicleClient: VehicleClient
    get() = engineOwner.binding.vehicleClient

  fun startInitialization() {
    engineOwner.startInitialization()
  }

  fun getOrCreateEngine(): FlutterEngine = engineOwner.getOrCreateEngine()

  fun sendRemoteCommand(command: NativeRemoteCommand) {
    engineOwner.binding.sendRemoteCommand(command)
  }
}
