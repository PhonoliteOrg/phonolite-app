package com.phonoliteorg.phonolite_app.infrastructure.media

import java.lang.ref.WeakReference

// Platform-main-thread ownership of a bound/started service and any pending start request.
internal class MediaServiceConnection(private val startService: () -> Unit, private val stopService: () -> Unit) {
  private var activeService: WeakReference<MediaServiceObserver>? = null
  private var startedOrRequested = false
  private var clearedSincePublication = false

  // A foreground start the service has not received yet. Stopping it then would break the
  // startForeground contract, so clear() leaves it to the service, which stops itself when empty.
  private var startPending = false

  fun attach(observer: MediaServiceObserver) {
    activeService = WeakReference(observer)
  }

  fun markStarted(observer: MediaServiceObserver) {
    if (activeService?.get() !== observer) {
      return
    }

    startPending = false

    if (!clearedSincePublication) {
      startedOrRequested = true
    }
  }

  fun detach(observer: MediaServiceObserver) {
    if (activeService?.get() !== observer) {
      return
    }

    activeService = null
    startedOrRequested = false
    startPending = false
    clearedSincePublication = false
  }

  fun publish(startIfNeeded: Boolean) {
    clearedSincePublication = false
    activeService?.get()?.applyState()

    if (startedOrRequested || !startIfNeeded) {
      return
    }

    startedOrRequested = true

    try {
      startService()
      startPending = true
    } catch (error: Throwable) {
      startedOrRequested = false
      throw error
    }
  }

  fun clear() {
    activeService?.get()?.clearState()
    startedOrRequested = false
    clearedSincePublication = true

    if (!startPending) {
      stopService()
    }
  }

  fun sourcesChanged() {
    activeService?.get()?.onSourcesChanged()
  }
}
