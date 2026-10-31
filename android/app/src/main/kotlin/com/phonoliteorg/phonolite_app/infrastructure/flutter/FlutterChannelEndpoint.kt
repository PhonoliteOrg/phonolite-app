package com.phonoliteorg.phonolite_app.infrastructure.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

interface FlutterChannelEndpoint {
  fun setHandler(handler: ((MethodCall, MethodChannel.Result) -> Unit)?)
  fun invoke(method: String, arguments: Any?, result: MethodChannel.Result?)
}
