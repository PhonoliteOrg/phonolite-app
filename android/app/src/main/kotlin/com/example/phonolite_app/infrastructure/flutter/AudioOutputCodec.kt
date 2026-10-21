package com.example.phonolite_app.infrastructure.flutter

import com.example.phonolite_app.data.models.audio.AudioOutputConfiguration
import com.example.phonolite_app.data.models.audio.OutputDevice

class AudioOutputCodec {
  fun configuration(values: Map<*, *>?): AudioOutputConfiguration? {
    val sampleRate = (values?.get("sampleRate") as? Number)?.toInt() ?: return null
    val channels = (values["channels"] as? Number)?.toInt() ?: return null
    val deviceId = (values["deviceId"] as? Number)?.toInt() ?: -1

    return AudioOutputConfiguration(sampleRate, channels, deviceId)
  }

  fun id(values: Map<*, *>?): Int? = (values?.get("id") as? Number)?.toInt()

  fun encodeDevices(devices: List<OutputDevice>): List<Map<String, Any>> = devices.map { device ->
    mapOf("id" to device.id, "name" to device.name)
  }
}
