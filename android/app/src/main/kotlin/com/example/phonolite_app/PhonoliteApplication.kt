package com.example.phonolite_app

import android.app.Application
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

class PhonoliteApplication : Application() {
  @Volatile
  private var flutterEngine: FlutterEngine? = null

  @Volatile
  private var platformBridge: PhonolitePlatformBridge? = null

  override fun onCreate() {
    super.onCreate()
    FlutterInjector.instance().flutterLoader().startInitialization(this)
  }

  fun getOrCreateFlutterEngine(): FlutterEngine {
    flutterEngine?.let { return it }
    synchronized(this) {
      flutterEngine?.let { return it }
      val loader = FlutterInjector.instance().flutterLoader()
      loader.ensureInitializationComplete(this, null)
      val engine = FlutterEngine(this)
      GeneratedPluginRegistrant.registerWith(engine)
      val bridge = PhonolitePlatformBridge(this, engine.dartExecutor.binaryMessenger)
      engine.dartExecutor.executeDartEntrypoint(
        DartExecutor.DartEntrypoint.createDefault(),
      )
      flutterEngine = engine
      platformBridge = bridge
      return engine
    }
  }

  fun getPlatformBridge(): PhonolitePlatformBridge {
    getOrCreateFlutterEngine()
    return checkNotNull(platformBridge)
  }
}
