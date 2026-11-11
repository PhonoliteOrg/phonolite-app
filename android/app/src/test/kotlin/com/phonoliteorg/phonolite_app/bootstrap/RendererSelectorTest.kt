package com.phonoliteorg.phonolite_app.bootstrap

// Dependency-free JVM checks of the renderer policy: no EGL context, PackageManager or Flutter engine.
object RendererSelectorTest {
  private const val ANDROID_9 = 28
  private const val ANDROID_12 = 31

  @JvmStatic
  fun main(args: Array<String>) {
    openGlFallbackAdrenoUsesSkia()
    vulkanCapableGpusKeepImpeller()
    olderAndroidKeepsTheEngineChoice()
    explicitManifestValueTakesPrecedence()

    println("RendererSelector: 4 headless JVM checks passed")
  }

  private fun openGlFallbackAdrenoUsesSkia() {
    check(RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 630"))
    check(RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 540"))
    check(RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 642L"))
    check(RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 650"))
  }

  private fun vulkanCapableGpusKeepImpeller() {
    check(!RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 660"))
    check(!RendererSelector.prefersSkia(null, ANDROID_12, "Adreno (TM) 740"))
    check(!RendererSelector.prefersSkia(null, ANDROID_12, "Mali-G78"))
    check(!RendererSelector.prefersSkia(null, ANDROID_12, null))
  }

  private fun olderAndroidKeepsTheEngineChoice() {
    check(!RendererSelector.prefersSkia(null, ANDROID_9, "Adreno (TM) 630"))
  }

  private fun explicitManifestValueTakesPrecedence() {
    check(!RendererSelector.prefersSkia(true, ANDROID_12, "Adreno (TM) 630"))
    check(!RendererSelector.prefersSkia(false, ANDROID_12, "Adreno (TM) 630"))
  }
}
