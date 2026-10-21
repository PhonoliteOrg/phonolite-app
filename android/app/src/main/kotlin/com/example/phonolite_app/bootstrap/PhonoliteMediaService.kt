package com.example.phonolite_app.bootstrap

import android.content.Intent
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import androidx.media.MediaBrowserServiceCompat
import com.example.phonolite_app.application.controllers.vehicle.VehicleBrowseController
import com.example.phonolite_app.data.models.playback.NativeRemoteCommand
import com.example.phonolite_app.data.models.vehicle.VehicleMediaIds
import com.example.phonolite_app.infrastructure.media.ArtworkDecoder
import com.example.phonolite_app.infrastructure.media.MediaMetadataFactory
import com.example.phonolite_app.infrastructure.media.MediaPendingIntents
import com.example.phonolite_app.infrastructure.media.MediaServiceActions
import com.example.phonolite_app.infrastructure.media.MediaServiceObserver
import com.example.phonolite_app.infrastructure.media.MediaSessionController
import com.example.phonolite_app.infrastructure.media.PlaybackNotificationController
import com.example.phonolite_app.ui.media.MediaItemFactory
import com.example.phonolite_app.ui.media.PlaybackNotificationFactory

class PhonoliteMediaService :
  MediaBrowserServiceCompat(),
  MediaServiceObserver {
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

    when (intent?.action) {
      MediaServiceActions.PLAY -> host.sendRemoteCommand(NativeRemoteCommand.Play)
      MediaServiceActions.PAUSE -> host.sendRemoteCommand(NativeRemoteCommand.Pause)
      MediaServiceActions.NEXT -> host.sendRemoteCommand(NativeRemoteCommand.Next)
      MediaServiceActions.PREVIOUS -> host.sendRemoteCommand(NativeRemoteCommand.Previous)
      MediaServiceActions.TOGGLE_LIKE -> host.sendRemoteCommand(NativeRemoteCommand.ToggleLike)
      MediaServiceActions.SYNC_STATE -> applyState()
    }

    mediaSession.handleIntent(intent)

    return START_STICKY
  }

  override fun onGetRoot(clientPackageName: String, clientUid: Int, rootHints: Bundle?): BrowserRoot =
    BrowserRoot(VehicleMediaIds.ROOT, null)

  override fun onLoadChildren(parentId: String, result: Result<MutableList<MediaBrowserCompat.MediaItem>>) {
    result.detach()
    browser.loadChildren(parentId) { nodes -> result.sendResult(nodes.mapTo(mutableListOf(), mediaItems::build)) }
  }

  override fun applyState() {
    val state = host.mediaController.latestState
    mediaSession.publish(state)

    if (state == null || !notifications.publish(state)) {
      clearState()
    }
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

  @Suppress("DEPRECATION") // Preserve the existing Boolean foreground removal contract.
  private fun assembleMediaOwners() {
    browser = VehicleBrowseController(host.vehicleClient) { host.mediaController.availability }

    val artwork = ArtworkDecoder()
    val intents = MediaPendingIntents(
      this,
      activityIntent = { Intent(this, MainActivity::class.java) },
      serviceIntent = { Intent(this, PhonoliteMediaService::class.java) }
    )
    val presentation = PlaybackNotificationFactory(this, intents::content, intents::service, artwork::decode)
    notifications = PlaybackNotificationController(
      this,
      presentation.channelName,
      presentation.channelDescription,
      createNotification = { state -> presentation.build(state, mediaSession.token) },
      startForeground = ::startForeground,
      stopForeground = ::stopForeground
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
