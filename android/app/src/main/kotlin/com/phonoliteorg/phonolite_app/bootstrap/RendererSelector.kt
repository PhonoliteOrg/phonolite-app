package com.phonoliteorg.phonolite_app.bootstrap

import android.content.Context
import android.content.pm.PackageManager
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import android.os.Build

/**
 * Chooses the Flutter renderer for this device before the engine starts.
 *
 * On Android 10+ the engine tries Impeller's Vulkan back end, but it treats Adreno 650 and older drivers as bad
 * and falls back to Impeller's OpenGL ES back end. On a Pixel 3 XL (Adreno 630) that fallback ran about 47 fps with
 * 10–12% of frames over 25 ms, while Skia ran 52 fps with about 3%. Those GPUs therefore start on Skia. Below
 * Android 10 the engine already selects Skia itself, and every other GPU keeps the engine's choice. An explicit
 * `EnableImpeller` manifest value still takes precedence.
 */
class RendererSelector(private val context: Context) {
  companion object {
    const val IMPELLER_MANIFEST_KEY = "io.flutter.embedding.android.EnableImpeller"
    const val SKIA_ENGINE_ARGUMENT = "--enable-impeller=false"

    // Mirrors the engine's kMinimumAndroidApiLevelForImpeller and DriverInfoVK::IsKnownBadDriver Adreno cutoff.
    private const val MIN_IMPELLER_API_LEVEL = Build.VERSION_CODES.Q
    private const val NEWEST_OPENGL_FALLBACK_ADRENO = 650
    private const val OLDEST_VULKAN_ADRENO_SERIES = 500
    private val ADRENO_MODEL = Regex("""Adreno \(TM\) (\d{3})""")

    fun prefersSkia(manifestValue: Boolean?, apiLevel: Int, gpuRenderer: String?): Boolean {
      if (manifestValue != null || apiLevel < MIN_IMPELLER_API_LEVEL) {
        return false
      }

      val model = gpuRenderer?.let { ADRENO_MODEL.find(it) }?.groupValues?.get(1)?.toInt() ?: return false

      return model in OLDEST_VULKAN_ADRENO_SERIES..NEWEST_OPENGL_FALLBACK_ADRENO
    }
  }

  /** Shell arguments for FlutterLoader; command-line arguments override manifest flags, so none are added then. */
  fun engineArguments(): Array<String>? {
    val apiLevel = Build.VERSION.SDK_INT

    // The GPU probe costs an EGL context, so skip it whenever the outcome is already decided.
    val manifestValue = manifestImpellerValue()
    if (manifestValue != null || apiLevel < MIN_IMPELLER_API_LEVEL) {
      return null
    }

    if (!prefersSkia(manifestValue, apiLevel, runCatching { glRenderer() }.getOrNull())) {
      return null
    }

    return arrayOf(SKIA_ENGINE_ARGUMENT)
  }

  private fun manifestImpellerValue(): Boolean? {
    val metaData =
      runCatching {
        @Suppress("DEPRECATION")
        context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
      }.getOrNull()

    if (metaData == null || !metaData.containsKey(IMPELLER_MANIFEST_KEY)) {
      return null
    }

    return metaData.getBoolean(IMPELLER_MANIFEST_KEY)
  }

  /**
   * Reads GL_RENDERER from a throwaway 1x1 pbuffer context. The display stays initialized because the engine
   * initializes the same default display next. Any failure keeps the engine's own renderer choice.
   */
  private fun glRenderer(): String? {
    val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    if (display == EGL14.EGL_NO_DISPLAY) {
      return null
    }

    val version = IntArray(2)
    if (!EGL14.eglInitialize(display, version, 0, version, 1)) {
      return null
    }

    val configAttributes =
      intArrayOf(
        EGL14.EGL_RENDERABLE_TYPE,
        EGL14.EGL_OPENGL_ES2_BIT,
        EGL14.EGL_SURFACE_TYPE,
        EGL14.EGL_PBUFFER_BIT,
        EGL14.EGL_NONE
      )
    val configs = arrayOfNulls<EGLConfig>(1)
    val configCount = IntArray(1)
    if (!EGL14.eglChooseConfig(display, configAttributes, 0, configs, 0, 1, configCount, 0) || configCount[0] == 0) {
      return null
    }

    val config = configs[0] ?: return null
    val contextAttributes = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
    val eglContext = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, contextAttributes, 0)
    if (eglContext == EGL14.EGL_NO_CONTEXT) {
      return null
    }

    val surfaceAttributes = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
    val surface = EGL14.eglCreatePbufferSurface(display, config, surfaceAttributes, 0)

    try {
      if (surface == EGL14.EGL_NO_SURFACE || !EGL14.eglMakeCurrent(display, surface, surface, eglContext)) {
        return null
      }

      return GLES20.glGetString(GLES20.GL_RENDERER)
    } finally {
      EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)

      if (surface != EGL14.EGL_NO_SURFACE) {
        EGL14.eglDestroySurface(display, surface)
      }

      EGL14.eglDestroyContext(display, eglContext)
      EGL14.eglReleaseThread()
    }
  }
}
