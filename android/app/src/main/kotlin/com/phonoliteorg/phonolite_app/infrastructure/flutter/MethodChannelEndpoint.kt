package com.phonoliteorg.phonolite_app.infrastructure.flutter

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MethodChannelEndpoint(messenger: BinaryMessenger, name: String) : FlutterChannelEndpoint {
  private val channel = MethodChannel(messenger, name)

  override fun setHandler(handler: ((MethodCall, MethodChannel.Result) -> Unit)?) {
    channel.setMethodCallHandler(handler?.let { callback -> MethodChannel.MethodCallHandler(callback) })
  }

  override fun invoke(method: String, arguments: Any?, result: MethodChannel.Result?) {
    channel.invokeMethod(method, arguments, result)
  }
}
