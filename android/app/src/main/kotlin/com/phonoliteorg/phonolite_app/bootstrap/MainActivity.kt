package com.phonoliteorg.phonolite_app.bootstrap

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun provideFlutterEngine(context: Context): FlutterEngine {
    val app = applicationContext as PhonoliteApplication

    return app.nativeHost.getOrCreateEngine()
  }

  override fun shouldDestroyEngineWithHost(): Boolean = false
}
