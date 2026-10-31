package com.phonoliteorg.phonolite_app.data.models.audio

data class AudioOutputConfiguration(
  val sampleRate: Int,
  val channels: Int,
  val deviceId: Int = -1,
  val bitsPerSample: Int = 16,
  val validBitsPerSample: Int = 16
)
