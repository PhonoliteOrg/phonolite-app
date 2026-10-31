package com.phonoliteorg.phonolite_app.infrastructure.media

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.media.session.MediaButtonReceiver
import com.phonoliteorg.phonolite_app.data.models.playback.NativeNowPlayingState
import com.phonoliteorg.phonolite_app.data.models.playback.NativeRemoteCommand

// The service owns this session; all callbacks and publication use the platform main thread.
class MediaSessionController(
  context: Context,
  contentIntent: PendingIntent,
  private val metadata: MediaMetadataFactory,
  private val sendRemoteCommand: (NativeRemoteCommand) -> Unit,
  private val playMediaId: (String) -> Unit,
  private val likeAction: (Boolean) -> PlaybackStateCompat.CustomAction
) {
  private val session = MediaSessionCompat(context, MediaServiceActions.SESSION_TAG)

  val token: MediaSessionCompat.Token
    get() = session.sessionToken

  init {
    session.setCallback(createCallback())
    @Suppress("DEPRECATION") // Existing compat-session flags remain part of this host's registration.
    session.setFlags(
      MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
    )
    session.setSessionActivity(contentIntent)
    session.isActive = true
  }

  fun release() {
    session.release()
  }

  fun handleIntent(intent: Intent?) {
    MediaButtonReceiver.handleIntent(session, intent)
  }

  fun publish(state: NativeNowPlayingState?) {
    session.isActive = state != null
    session.setMetadata(metadata.build(state))
    session.setPlaybackState(buildPlaybackState(state))
  }

  fun clear() {
    session.setMetadata(null)
    session.setPlaybackState(buildPlaybackState(null))
  }

  private fun buildPlaybackState(state: NativeNowPlayingState?): PlaybackStateCompat {
    if (state == null || state.trackId.isBlank()) {
      return PlaybackStateCompat.Builder()
        .setActions(PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID)
        .setState(PlaybackStateCompat.STATE_STOPPED, 0L, 0f, SystemClock.elapsedRealtime())
        .build()
    }

    val actions = PlaybackStateCompat.ACTION_PLAY or
      PlaybackStateCompat.ACTION_PAUSE or
      PlaybackStateCompat.ACTION_PLAY_PAUSE or
      PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
      PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
      PlaybackStateCompat.ACTION_SEEK_TO or
      PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID

    return PlaybackStateCompat.Builder()
      .setActions(actions)
      .setState(
        if (state.isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
        state.positionMs,
        if (state.isPlaying) 1f else 0f,
        SystemClock.elapsedRealtime()
      )
      .addCustomAction(likeAction(state.liked))
      .build()
  }

  private fun createCallback(): MediaSessionCompat.Callback = object : MediaSessionCompat.Callback() {
    override fun onPlay() = sendRemoteCommand(NativeRemoteCommand.Play)

    override fun onPause() = sendRemoteCommand(NativeRemoteCommand.Pause)

    override fun onStop() = sendRemoteCommand(NativeRemoteCommand.Pause)

    override fun onSkipToNext() = sendRemoteCommand(NativeRemoteCommand.Next)

    override fun onSkipToPrevious() = sendRemoteCommand(NativeRemoteCommand.Previous)

    override fun onSeekTo(pos: Long) = sendRemoteCommand(NativeRemoteCommand.Seek(pos / 1000.0))

    override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
      if (mediaId != null) {
        playMediaId(mediaId)
      }
    }

    override fun onCustomAction(action: String?, extras: Bundle?) {
      if (action == MediaServiceActions.TOGGLE_LIKE) {
        sendRemoteCommand(NativeRemoteCommand.ToggleLike)
      }
    }
  }
}
