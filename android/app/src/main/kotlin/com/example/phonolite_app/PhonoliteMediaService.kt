package com.example.phonolite_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.MediaBrowserServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import java.lang.ref.WeakReference

class PhonoliteMediaService : MediaBrowserServiceCompat() {
  companion object {
    private const val notificationChannelId = "phonolite.playback"
    private const val notificationId = 3010
    private const val sessionTag = "phonolite_media_session"

    private const val rootId = "root"
    private const val homeId = "home"
    private const val artistsId = "artists"
    private const val playlistsId = "playlists"
    private const val likedId = "liked"
    private const val artistPrefix = "artist:"
    private const val albumPrefix = "album:"
    private const val playlistPrefix = "playlist:"
    private const val actionPrefix = "action:"
    private const val messagePrefix = "message:"

    private const val actionSyncState = "com.example.phonolite_app.SYNC_STATE"
    private const val actionPlay = "com.example.phonolite_app.PLAY"
    private const val actionPause = "com.example.phonolite_app.PAUSE"
    private const val actionNext = "com.example.phonolite_app.NEXT"
    private const val actionPrev = "com.example.phonolite_app.PREV"
    private const val actionToggleLike = "com.example.phonolite_app.TOGGLE_LIKE"

    @Volatile
    private var latestState: PhonoliteNowPlayingState? = null

    @Volatile
    private var authorized: Boolean = false

    @Volatile
    private var activeService: WeakReference<PhonoliteMediaService>? = null

    fun publishNowPlaying(context: Context, state: PhonoliteNowPlayingState) {
      latestState = state
      activeService?.get()?.applyState()
      val intent = Intent(context, PhonoliteMediaService::class.java).setAction(actionSyncState)
      ContextCompat.startForegroundService(context, intent)
    }

    fun clearNowPlaying(context: Context) {
      latestState = null
      activeService?.get()?.clearState()
      context.stopService(Intent(context, PhonoliteMediaService::class.java))
    }

    fun updateAuthorization(_context: Context, isAuthorized: Boolean) {
      authorized = isAuthorized
      activeService?.get()?.onAuthorizationChanged()
    }
  }

  private val bridge: PhonolitePlatformBridge
    get() = (applicationContext as PhonoliteApplication).getPlatformBridge()

  private val notificationManager: NotificationManager by lazy {
    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  }

  private val mediaSession: MediaSessionCompat by lazy {
    MediaSessionCompat(this, sessionTag).apply {
      setCallback(sessionCallback)
      setFlags(
        MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
          MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
      )
      setSessionActivity(buildContentIntent())
      isActive = true
    }
  }

  private var isForeground = false

  private val sessionCallback =
    object : MediaSessionCompat.Callback() {
      override fun onPlay() {
        bridge.sendRemoteCommand("play")
      }

      override fun onPause() {
        bridge.sendRemoteCommand("pause")
      }

      override fun onStop() {
        bridge.sendRemoteCommand("pause")
      }

      override fun onSkipToNext() {
        bridge.sendRemoteCommand("next")
      }

      override fun onSkipToPrevious() {
        bridge.sendRemoteCommand("prev")
      }

      override fun onSeekTo(pos: Long) {
        bridge.sendRemoteCommand("seek", mapOf("position" to pos / 1000.0))
      }

      override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
        if (mediaId != null) {
          handlePlayableItem(mediaId)
        }
      }

      override fun onCustomAction(action: String?, extras: Bundle?) {
        if (action == actionToggleLike) {
          bridge.sendRemoteCommand("toggleLike")
        }
      }
    }

  override fun onCreate() {
    super.onCreate()
    activeService = WeakReference(this)
    createNotificationChannel()
    sessionToken = mediaSession.sessionToken
    mediaSession.isActive = true
    onAuthorizationChanged()
    applyState()
  }

  override fun onDestroy() {
    if (activeService?.get() === this) {
      activeService = null
    }
    mediaSession.release()
    notificationManager.cancel(notificationId)
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      actionPlay -> bridge.sendRemoteCommand("play")
      actionPause -> bridge.sendRemoteCommand("pause")
      actionNext -> bridge.sendRemoteCommand("next")
      actionPrev -> bridge.sendRemoteCommand("prev")
      actionToggleLike -> bridge.sendRemoteCommand("toggleLike")
      actionSyncState -> applyState()
    }
    MediaButtonReceiver.handleIntent(mediaSession, intent)
    return START_STICKY
  }

  override fun onGetRoot(
    clientPackageName: String,
    clientUid: Int,
    rootHints: Bundle?,
  ): BrowserRoot {
    return BrowserRoot(rootId, null)
  }

  override fun onLoadChildren(
    parentId: String,
    result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
  ) {
    result.detach()
    when {
      parentId == rootId -> loadRootChildren(result)
      parentId == homeId -> loadVehicleList(
        method = "getHomeActions",
        result = result,
      ) { entry ->
        buildItem(
          mediaId = if (entry.enabled) "${actionPrefix}${entry.id}" else "${messagePrefix}${entry.id}",
          title = entry.title,
          subtitle = entry.subtitle,
          playable = true,
        )
      }
      parentId == artistsId -> loadVehicleList(
        method = "getArtists",
        result = result,
      ) { entry ->
        buildItem(
          mediaId = "${artistPrefix}${entry.id}",
          title = entry.title,
          subtitle = entry.subtitle,
          browsable = true,
        )
      }
      parentId == playlistsId -> loadVehicleList(
        method = "getPlaylists",
        result = result,
      ) { entry ->
        buildItem(
          mediaId = if (entry.enabled) "${playlistPrefix}${entry.id}" else "${messagePrefix}${entry.id}",
          title = entry.title,
          subtitle = entry.subtitle,
          playable = true,
        )
      }
      parentId.startsWith(artistPrefix) -> {
        val artistId = parentId.removePrefix(artistPrefix)
        loadVehicleList(
          method = "getAlbums",
          arguments = mapOf("artistId" to artistId),
          result = result,
        ) { entry ->
          buildItem(
            mediaId = if (entry.enabled) "${albumPrefix}${entry.id}" else "${messagePrefix}${entry.id}",
            title = entry.title,
            subtitle = entry.subtitle,
            playable = true,
          )
        }
      }
      else -> result.sendResult(mutableListOf())
    }
  }

  private fun loadRootChildren(
    result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
  ) {
    if (!authorized) {
      result.sendResult(
        mutableListOf(
          buildItem(
            mediaId = "${messagePrefix}logged_out",
            title = "Open Phonolite to log in",
            subtitle = "Connect to a server to browse your library",
            playable = true,
          ),
        ),
      )
      return
    }
    bridge.invokeVehicleMethod("getLibraryStatus") { response ->
      val likedAvailable =
        ((response.value as? Map<*, *>)?.get("likedAvailable") as? Boolean) ?: false
      val items =
        mutableListOf(
          buildItem(
            mediaId = homeId,
            title = "Home",
            subtitle = "Shuffle actions",
            browsable = true,
          ),
          buildItem(
            mediaId = artistsId,
            title = "Artists",
            subtitle = "Browse by artist",
            browsable = true,
          ),
          buildItem(
            mediaId = playlistsId,
            title = "Playlists",
            subtitle = "Browse playlists",
            browsable = true,
          ),
        )
      if (likedAvailable) {
        items.add(
          buildItem(
            mediaId = likedId,
            title = "Liked Songs",
            subtitle = "Play from the top",
            playable = true,
          ),
        )
      }
      result.sendResult(items)
    }
  }

  private fun loadVehicleList(
    method: String,
    result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
    arguments: Any? = null,
    itemBuilder: (VehicleEntry) -> MediaBrowserCompat.MediaItem,
  ) {
    bridge.invokeVehicleMethod(method, arguments) { response ->
      val parsed = parseVehicleEntries(response)
      if (parsed.error != null) {
        result.sendResult(
          mutableListOf(
            buildItem(
              mediaId = "${messagePrefix}${method}_error",
              title = "Phonolite",
              subtitle = parsed.error,
              playable = true,
            ),
          ),
        )
        return@invokeVehicleMethod
      }
      if (parsed.items.isEmpty()) {
        result.sendResult(
          mutableListOf(
            buildItem(
              mediaId = "${messagePrefix}${method}_empty",
              title = "Nothing here yet",
              subtitle = "Open Phonolite on your phone for more options",
              playable = true,
            ),
          ),
        )
        return@invokeVehicleMethod
      }
      result.sendResult(parsed.items.mapTo(mutableListOf(), itemBuilder))
    }
  }

  private fun parseVehicleEntries(response: BridgeInvokeResult): VehicleResult {
    if (response.notImplemented) {
      return VehicleResult(error = "Phonolite is still loading")
    }
    if (response.error != null) {
      return VehicleResult(error = response.error)
    }
    val payload = response.value as? Map<*, *> ?: return VehicleResult(error = "Unavailable")
    val error = payload["error"]?.toString()
    if (!error.isNullOrBlank()) {
      return VehicleResult(error = error)
    }
    val rawItems = payload["items"] as? List<*> ?: emptyList<Any?>()
    val items =
      rawItems.mapNotNull { raw ->
        val map = raw as? Map<*, *> ?: return@mapNotNull null
        val id = map["id"]?.toString().orEmpty()
        val title = map["title"]?.toString().orEmpty()
        if (id.isEmpty() || title.isEmpty()) {
          return@mapNotNull null
        }
        VehicleEntry(
          id = id,
          title = title,
          subtitle = map["subtitle"]?.toString(),
          enabled = map["enabled"] as? Boolean ?: true,
        )
      }
    return VehicleResult(items = items)
  }

  private fun handlePlayableItem(mediaId: String) {
    when {
      mediaId == likedId -> {
        bridge.invokeVehicleMethod("playLiked") {}
      }
      mediaId.startsWith(actionPrefix) -> {
        val actionId = mediaId.removePrefix(actionPrefix)
        when (actionId) {
          "startLibraryShuffle" -> bridge.invokeVehicleMethod("startLibraryShuffle") {}
          "startLikedShuffle" -> bridge.invokeVehicleMethod("startLikedShuffle") {}
          "startCustomShuffle" -> bridge.invokeVehicleMethod("startCustomShuffle") {}
        }
      }
      mediaId.startsWith(albumPrefix) -> {
        val albumId = mediaId.removePrefix(albumPrefix)
        bridge.invokeVehicleMethod("playAlbum", mapOf("albumId" to albumId)) {}
      }
      mediaId.startsWith(playlistPrefix) -> {
        val playlistId = mediaId.removePrefix(playlistPrefix)
        bridge.invokeVehicleMethod("playPlaylist", mapOf("playlistId" to playlistId)) {}
      }
    }
  }

  fun onAuthorizationChanged() {
    notifyChildrenChanged(rootId)
    notifyChildrenChanged(homeId)
    notifyChildrenChanged(artistsId)
    notifyChildrenChanged(playlistsId)
  }

  fun applyState() {
    val state = latestState
    mediaSession.isActive = state != null
    mediaSession.setMetadata(buildMetadata(state))
    mediaSession.setPlaybackState(buildPlaybackState(state))
    if (state == null) {
      clearState()
      return
    }
    val currentState = state
    val notification = buildNotification(currentState)
    if (notification == null) {
      clearState()
      return
    }
    if (!isForeground) {
      startForeground(notificationId, notification)
      isForeground = true
    } else {
      notificationManager.notify(notificationId, notification)
    }
    if (!currentState.isPlaying) {
      stopForeground(false)
      isForeground = false
      notificationManager.notify(notificationId, notification)
    }
  }

  fun clearState() {
    mediaSession.setMetadata(null)
    mediaSession.setPlaybackState(buildPlaybackState(null))
    notificationManager.cancel(notificationId)
    if (isForeground) {
      stopForeground(true)
      isForeground = false
    }
  }

  private fun buildMetadata(state: PhonoliteNowPlayingState?): MediaMetadataCompat? {
    if (state == null || state.trackId.isBlank()) {
      return null
    }
    val builder =
      MediaMetadataCompat.Builder()
        .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, state.trackId)
        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, state.title)
        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, state.artist)
        .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, state.album)
        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, state.durationMs)
    decodeArtwork(state.artworkBytes)?.let { bitmap ->
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bitmap)
      builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, bitmap)
    }
    return builder.build()
  }

  private fun buildPlaybackState(state: PhonoliteNowPlayingState?): PlaybackStateCompat {
    if (state == null || state.trackId.isBlank()) {
      return PlaybackStateCompat.Builder()
        .setActions(
          PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID,
        )
        .setState(
          PlaybackStateCompat.STATE_STOPPED,
          0L,
          0f,
          SystemClock.elapsedRealtime(),
        )
        .build()
    }
    val actions =
      PlaybackStateCompat.ACTION_PLAY or
        PlaybackStateCompat.ACTION_PAUSE or
        PlaybackStateCompat.ACTION_PLAY_PAUSE or
        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
        PlaybackStateCompat.ACTION_SEEK_TO or
        PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID
    val builder =
      PlaybackStateCompat.Builder()
        .setActions(actions)
        .setState(
          if (state.isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
          state.positionMs,
          if (state.isPlaying) 1f else 0f,
          SystemClock.elapsedRealtime(),
        )
        .addCustomAction(
          PlaybackStateCompat.CustomAction.Builder(
            actionToggleLike,
            if (state.liked) "Unlike" else "Like",
            if (state.liked) android.R.drawable.btn_star_big_on else android.R.drawable.btn_star_big_off,
          ).build(),
        )
    return builder.build()
  }

  private fun buildNotification(state: PhonoliteNowPlayingState?): Notification? {
    if (state == null || state.trackId.isBlank()) {
      return null
    }
    val playPauseAction =
      if (state.isPlaying) {
        notificationAction(
          icon = android.R.drawable.ic_media_pause,
          title = "Pause",
          action = actionPause,
        )
      } else {
        notificationAction(
          icon = android.R.drawable.ic_media_play,
          title = "Play",
          action = actionPlay,
        )
      }
    val builder =
      NotificationCompat.Builder(this, notificationChannelId)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(if (state.title.isBlank()) "Phonolite" else state.title)
        .setContentText(
          listOf(state.artist, state.album)
            .filter { it.isNotBlank() }
            .joinToString(" - ")
            .ifBlank { "Now Playing" },
        )
        .setContentIntent(buildContentIntent())
        .setDeleteIntent(buildServiceIntent(actionPause, 10))
        .setOnlyAlertOnce(true)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
        .setOngoing(state.isPlaying)
        .setShowWhen(false)
        .setStyle(
          MediaStyle()
            .setMediaSession(mediaSession.sessionToken)
            .setShowActionsInCompactView(0, 1, 2),
        )
        .addAction(
          notificationAction(
            icon = android.R.drawable.ic_media_previous,
            title = "Previous",
            action = actionPrev,
          ),
        )
        .addAction(playPauseAction)
        .addAction(
          notificationAction(
            icon = android.R.drawable.ic_media_next,
            title = "Next",
            action = actionNext,
          ),
        )
        .addAction(
          notificationAction(
            icon = if (state.liked) android.R.drawable.btn_star_big_on else android.R.drawable.btn_star_big_off,
            title = if (state.liked) "Unlike" else "Like",
            action = actionToggleLike,
          ),
        )
    decodeArtwork(state.artworkBytes)?.let { bitmap ->
      builder.setLargeIcon(bitmap)
    }
    return builder.build()
  }

  private fun notificationAction(
    icon: Int,
    title: String,
    action: String,
  ): NotificationCompat.Action {
    return NotificationCompat.Action.Builder(
      icon,
      title,
      buildServiceIntent(action, action.hashCode()),
    ).build()
  }

  private fun buildServiceIntent(action: String, requestCode: Int): PendingIntent {
    val intent = Intent(this, PhonoliteMediaService::class.java).setAction(action)
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getService(this, requestCode, intent, flags)
  }

  private fun buildContentIntent(): PendingIntent {
    val intent =
      Intent(this, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getActivity(this, 100, intent, flags)
  }

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val channel =
      NotificationChannel(
        notificationChannelId,
        "Phonolite playback",
        NotificationManager.IMPORTANCE_LOW,
      )
    channel.description = "Playback controls and now playing updates"
    notificationManager.createNotificationChannel(channel)
  }

  private fun decodeArtwork(bytes: ByteArray?): Bitmap? {
    if (bytes == null || bytes.isEmpty()) {
      return null
    }
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
  }

  private data class VehicleEntry(
    val id: String,
    val title: String,
    val subtitle: String?,
    val enabled: Boolean,
  )

  private data class VehicleResult(
    val items: List<VehicleEntry> = emptyList(),
    val error: String? = null,
  )

  private fun buildItem(
    mediaId: String,
    title: String,
    subtitle: String?,
    browsable: Boolean = false,
    playable: Boolean = false,
  ): MediaBrowserCompat.MediaItem {
    val description =
      MediaDescriptionCompat.Builder()
        .setMediaId(mediaId)
        .setTitle(title)
        .setSubtitle(subtitle)
        .build()
    val flags =
      when {
        browsable -> MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
        playable -> MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
        else -> MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
      }
    return MediaBrowserCompat.MediaItem(description, flags)
  }
}
