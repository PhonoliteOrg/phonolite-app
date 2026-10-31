package com.phonoliteorg.phonolite_app.infrastructure.audio

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.phonoliteorg.phonolite_app.data.models.audio.OutputDevice

internal class OutputDeviceCatalog(private val audioManager: AudioManager) {
  private data class DeviceEntry(val device: OutputDevice, val routeKey: String)

  fun listOutputDevices(): List<OutputDevice> {
    val devices = mutableListOf(OutputDevice(-1, "System Default"))

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return devices
    }

    val seenIds = HashSet<Int>()
    val seenRouteKeys = HashSet<String>()
    audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).forEach { device ->
      if (!seenIds.add(device.id)) {
        return@forEach
      }

      val entry = deviceEntry(device) ?: return@forEach

      if (!seenRouteKeys.add(entry.routeKey)) {
        return@forEach
      }

      devices.add(entry.device)
    }

    return devices
  }

  private fun deviceEntry(device: AudioDeviceInfo): DeviceEntry? {
    val name = deviceDisplayName(device) ?: return null
    val routeKey =
      if (isBuiltInOutputType(device.type)) {
        "builtin:$name"
      } else {
        "device:${device.id}"
      }

    return DeviceEntry(OutputDevice(device.id, name), routeKey)
  }

  private fun deviceDisplayName(device: AudioDeviceInfo): String? {
    val label = device.productName?.toString()?.trim().orEmpty()

    return when (device.type) {
      AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone Earpiece"
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Device Speaker"
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "Device Speaker"
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> label.ifEmpty { "Bluetooth Audio" }
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> label.ifEmpty { "Bluetooth Headset" }
      AudioDeviceInfo.TYPE_DOCK -> "Dock"
      AudioDeviceInfo.TYPE_HDMI,
      AudioDeviceInfo.TYPE_HDMI_ARC,
      AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI"
      AudioDeviceInfo.TYPE_LINE_ANALOG,
      AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Line Out"
      AudioDeviceInfo.TYPE_USB_DEVICE,
      AudioDeviceInfo.TYPE_USB_HEADSET -> label.ifEmpty { "USB Audio" }
      AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> label.ifEmpty { "Headphones" }
      AudioDeviceInfo.TYPE_WIRED_HEADSET -> label.ifEmpty { "Wired Headset" }
      AudioDeviceInfo.TYPE_AUX_LINE -> label.ifEmpty { "Aux Output" }
      AudioDeviceInfo.TYPE_HEARING_AID -> label.ifEmpty { "Hearing Aid" }
      AudioDeviceInfo.TYPE_BUS,
      AudioDeviceInfo.TYPE_REMOTE_SUBMIX,
      AudioDeviceInfo.TYPE_TELEPHONY,
      AudioDeviceInfo.TYPE_UNKNOWN -> null
      else -> label.ifEmpty { "Output ${device.id}" }
    }
  }

  private fun isBuiltInOutputType(type: Int): Boolean = when (type) {
    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> true
    else -> false
  }
}
