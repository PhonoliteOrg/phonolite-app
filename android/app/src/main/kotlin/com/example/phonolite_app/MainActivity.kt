package com.example.phonolite_app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun provideFlutterEngine(context: Context): FlutterEngine {
    val app = applicationContext as PhonoliteApplication
    return app.getOrCreateFlutterEngine()
  }

  override fun shouldDestroyEngineWithHost(): Boolean = false
}
