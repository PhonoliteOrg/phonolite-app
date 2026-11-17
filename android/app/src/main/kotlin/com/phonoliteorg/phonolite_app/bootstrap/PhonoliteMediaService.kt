package com.phonoliteorg.phonolite_app.bootstrap

import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.support.v4.media.MediaBrowserCompat
import androidx.core.app.ServiceCompat
import androidx.media.MediaBrowserServiceCompat
import com.phonoliteorg.phonolite_app.application.controllers.vehicle.VehicleBrowseController
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleMediaIds
import com.phonoliteorg.phonolite_app.infrastructure.media.ArtworkDecoder
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaMetadataFactory
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaPendingIntents
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaServiceActions
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaServiceObserver
import com.phonoliteorg.phonolite_app.infrastructure.media.MediaSessionController
import com.phonoliteorg.phonolite_app.infrastructure.media.PlaybackNotificationController
import com.phonoliteorg.phonolite_app.ui.media.MediaItemFactory
import com.phonoliteorg.phonolite_app.ui.media.PlaybackNotificationFactory

class PhonoliteMediaService :
  MediaBrowserServiceCompat(),
  MediaServiceObserver {
  companion object {
    // Root handed to browsers outside the trusted set: they may connect for the session token but see no library.
    private const val EMPTY_ROOT = "empty_root"

    // Browse surfaces allowed to read the library. MediaBrowserServiceCompat verifies the package against the uid.
    private val TRUSTED_BROWSER_PACKAGES = setOf(
      "com.google.android.projection.gearhead", // Android Auto
      "com.google.android.carassistant", // Android Auto assistant
      "com.android.car.media", // Android Automotive OS media center
      "com.android.systemui", // Media controls and resumption
      "com.google.android.googlequicksearchbox" // Google Assistant
    )
  }

  private lateinit var host: NativeHost
  private lateinit var browser: VehicleBrowseController
  private lateinit var mediaSession: MediaSessionController
  private lateinit var notifications: PlaybackNotificationController
  private val mediaItems = MediaItemFactory()

  override fun onCreate() {
    super.onCreate()
    host = (applicationContext as PhonoliteApplication).nativeHost
    host.getOrCreateEngine()

    assembleMediaOwners()
    host.mediaServiceGateway.attach(this)
    sessionToken = mediaSession.token
    onSourcesChanged()
    applyState()
  }

  override fun onDestroy() {
    host.mediaServiceGateway.detach(this)
    mediaSession.release()
    notifications.destroy()
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    host.mediaServiceGateway.markStarted(this)

    // Transport actions arrive through MediaActionReceiver; this exported service only accepts state syncs
    // (sent by startForegroundService) and media buttons.
    if (intent?.action == MediaServiceActions.SYNC_STATE) {
      notifications.fulfillForegroundStart(host.mediaController.latestState)

      if (!publishState()) {
        stopSelf(startId)
      }
    }

    mediaSession.handleIntent(intent)

    // A restart after process death would boot the Flutter engine headless with nothing to play.
    return START_NOT_STICKY
  }

  override fun onGetRoot(clientPackageName: String, clientUid: Int, rootHints: Bundle?): BrowserRoot {
    if (!isTrustedBrowser(clientPackageName, clientUid)) {
      return BrowserRoot(EMPTY_ROOT, null)
    }

    return BrowserRoot(VehicleMediaIds.ROOT, null)
  }

  override fun onLoadChildren(parentId: String, result: Result<MutableList<MediaBrowserCompat.MediaItem>>) {
    // Untrusted browsers can still subscribe to any id directly, so the check repeats per load.
    val caller = currentBrowserInfo
    if (parentId == EMPTY_ROOT || !isTrustedBrowser(caller.packageName, caller.uid)) {
      result.sendResult(mutableListOf())
      return
    }

    result.detach()
    browser.loadChildren(parentId) { nodes -> result.sendResult(nodes.mapTo(mutableListOf(), mediaItems::build)) }
  }

  override fun applyState() {
    publishState()
  }

  override fun clearState() {
    mediaSession.clear()
    notifications.clear()
  }

  override fun onSourcesChanged() {
    notifyChildrenChanged(VehicleMediaIds.ROOT)
    notifyChildrenChanged(VehicleMediaIds.SERVER_ROOT)
    notifyChildrenChanged(VehicleMediaIds.LOCAL_ROOT)
    notifyChildrenChanged(VehicleMediaIds.HOME)
    notifyChildrenChanged(VehicleMediaIds.ARTISTS)
    notifyChildrenChanged(VehicleMediaIds.PLAYLISTS)
    notifyChildrenChanged(VehicleMediaIds.LOCAL_ARTISTS)
    notifyChildrenChanged(VehicleMediaIds.LOCAL_PLAYLISTS)
  }

  // Returns whether a notification is now shown; otherwise the session and notification are cleared.
  private fun publishState(): Boolean {
    val state = host.mediaController.latestState
    mediaSession.publish(state)

    if (state == null || !notifications.publish(state)) {
      clearState()
      return false
    }

    return true
  }

  private fun isTrustedBrowser(packageName: String, uid: Int): Boolean =
    uid == Process.myUid() || uid == Process.SYSTEM_UID || packageName in TRUSTED_BROWSER_PACKAGES

  private fun assembleMediaOwners() {
    browser = VehicleBrowseController(host.vehicleClient) { host.mediaController.availability }

    val artwork = ArtworkDecoder()
    val intents = MediaPendingIntents(
      this,
      activityIntent = { Intent(this, MainActivity::class.java) },
      actionIntent = { Intent(this, MediaActionReceiver::class.java) }
    )
    val presentation = PlaybackNotificationFactory(this, intents::content, intents::action, artwork::decode)
    notifications = PlaybackNotificationController(
      this,
      presentation.channelName,
      presentation.channelDescription,
      createNotification = { state -> presentation.build(state, mediaSession.token) },
      createPlaceholder = presentation::placeholder,
      startForeground = ::startForeground,
      stopForeground = { flags -> ServiceCompat.stopForeground(this, flags) }
    )
    notifications.initialize()

    mediaSession = MediaSessionController(
      this,
      intents.content(),
      MediaMetadataFactory(artwork),
      host::sendRemoteCommand,
      browser::play,
      presentation::likeAction
    )
  }
}
