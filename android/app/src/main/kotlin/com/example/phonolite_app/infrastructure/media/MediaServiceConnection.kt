package com.example.phonolite_app.infrastructure.media

import java.lang.ref.WeakReference

// Platform-main-thread ownership of a bound/started service and any pending start request.
internal class MediaServiceConnection(private val startService: () -> Unit, private val stopService: () -> Unit) {
  private var activeService: WeakReference<MediaServiceObserver>? = null
  private var startedOrRequested = false
  private var clearedSincePublication = false

  fun attach(observer: MediaServiceObserver) {
    activeService = WeakReference(observer)
  }

  fun markStarted(observer: MediaServiceObserver) {
    if (activeService?.get() === observer && !clearedSincePublication) {
      startedOrRequested = true
    }
  }

  fun detach(observer: MediaServiceObserver) {
    if (activeService?.get() !== observer) {
      return
    }

    activeService = null
    startedOrRequested = false
    clearedSincePublication = false
  }

  fun publish() {
    clearedSincePublication = false
    activeService?.get()?.applyState()

    if (startedOrRequested) {
      return
    }

    startedOrRequested = true

    try {
      startService()
    } catch (error: Throwable) {
      startedOrRequested = false
      throw error
    }
  }

  fun clear() {
    activeService?.get()?.clearState()
    startedOrRequested = false
    clearedSincePublication = true

    stopService()
  }

  fun sourcesChanged() {
    activeService?.get()?.onSourcesChanged()
  }
}
