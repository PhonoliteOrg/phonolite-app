package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.infrastructure.network.NetworkRouteMonitor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class NetworkRouteChannelAdapter(messenger: BinaryMessenger, private val monitor: NetworkRouteMonitor) {
  private val channel = EventChannel(messenger, "com.phonoliteorg.phonolite_app/network_routes")
  private var attached = false
  private val handler = object : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
      try {
        monitor.start { revision -> events.success(revision) }
      } catch (_: RuntimeException) {
        monitor.stop()
        events.error("unavailable", "Native network route monitoring unavailable", null)
      }
    }

    override fun onCancel(arguments: Any?) {
      monitor.stop()
    }
  }

  fun attach() {
    if (attached) {
      return
    }

    channel.setStreamHandler(handler)
    attached = true
  }

  fun detach() {
    stopObserving()
    channel.setStreamHandler(null)
    attached = false
  }

  fun stopObserving() {
    monitor.stop()
  }
}
