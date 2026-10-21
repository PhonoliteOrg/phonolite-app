package com.example.phonolite_app.bootstrap

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.BinaryMessenger

class FlutterEngineOwner(context: Context, private val createBinding: (BinaryMessenger) -> FlutterEngineBinding) {
  private val appContext = context.applicationContext

  @Volatile
  private var session: EngineSession? = null

  val binding: FlutterEngineBinding
    get() = getOrCreateSession().binding

  fun startInitialization() {
    FlutterInjector.instance().flutterLoader().startInitialization(appContext)
  }

  fun getOrCreateEngine(): FlutterEngine = getOrCreateSession().engine

  private fun getOrCreateSession(): EngineSession {
    session?.let { return it }

    return synchronized(this) {
      session?.let { return@synchronized it }

      val loader = FlutterInjector.instance().flutterLoader()
      loader.ensureInitializationComplete(appContext, null)

      // Registration remains explicit and runs once before channel binding and Dart startup.
      val engine = FlutterEngine(appContext, null, false)
      GeneratedPluginRegister.registerGeneratedPlugins(engine)

      val binding = createBinding(engine.dartExecutor.binaryMessenger)
      binding.attach()
      engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())

      val created = EngineSession(engine, binding)
      session = created

      created
    }
  }

  private class EngineSession(val engine: FlutterEngine, val binding: FlutterEngineBinding)
}
