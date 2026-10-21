package com.example.phonolite_app.infrastructure.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

abstract class FlutterChannelAdapter(
  private val endpoint: FlutterChannelEndpoint,
  private val dispatchToPlatform: (() -> Unit) -> Unit
) {
  private var attached = false

  fun attach() {
    if (attached) {
      return
    }

    endpoint.setHandler(::handleCall)
    attached = true
  }

  fun detach() {
    if (!attached) {
      return
    }

    endpoint.setHandler(null)
    attached = false
  }

  protected abstract fun handleCall(call: MethodCall, result: MethodChannel.Result)

  protected fun invoke(method: String, arguments: Any? = null, result: MethodChannel.Result? = null) {
    dispatchToPlatform {
      if (attached) {
        endpoint.invoke(method, arguments, result)
      } else {
        result?.notImplemented()
      }
    }
  }

  protected fun <T> request(
    method: String,
    arguments: Any?,
    decode: (Any?) -> T,
    failure: (String?, Boolean) -> T,
    completion: (T) -> Unit
  ) {
    invoke(
      method,
      arguments,
      object : MethodChannel.Result {
        override fun success(result: Any?) {
          completion(decode(result))
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
          completion(failure(errorMessage ?: errorCode, false))
        }

        override fun notImplemented() {
          completion(failure(null, true))
        }
      }
    )
  }
}
