package com.example.phonolite_app.infrastructure.flutter

import com.example.phonolite_app.application.controllers.media.NativeMediaController
import com.example.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.example.phonolite_app.data.models.vehicle.VehicleHomeAction
import com.example.phonolite_app.data.models.vehicle.VehicleLibraryStatus
import com.example.phonolite_app.data.models.vehicle.VehicleScope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VehicleChannelAdapter(
  endpoint: FlutterChannelEndpoint,
  dispatchToPlatform: (() -> Unit) -> Unit,
  private val media: NativeMediaController,
  private val codec: VehicleCodec = VehicleCodec()
) : FlutterChannelAdapter(endpoint, dispatchToPlatform),
  VehicleClient {
  override fun loadLibraryStatus(scope: VehicleScope, completion: (VehicleLibraryStatus) -> Unit) {
    request("getLibraryStatus", codec.arguments(scope), codec::decodeLibraryStatus, { _, _ ->
      VehicleLibraryStatus()
    }, completion)
  }

  override fun loadHomeActions(completion: (VehicleBrowseResult) -> Unit) {
    loadEntries("getHomeActions", null, completion)
  }

  override fun loadArtists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
    loadEntries("getArtists", codec.arguments(scope), completion)
  }

  override fun loadPlaylists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
    loadEntries("getPlaylists", codec.arguments(scope), completion)
  }

  override fun loadAlbums(artistId: String, scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
    loadEntries("getAlbums", codec.arguments(scope, "artistId", artistId), completion)
  }

  override fun playLiked(scope: VehicleScope) {
    invoke("playLiked", codec.arguments(scope))
  }

  override fun playAlbum(albumId: String, scope: VehicleScope) {
    invoke("playAlbum", codec.arguments(scope, "albumId", albumId))
  }

  override fun playPlaylist(playlistId: String, scope: VehicleScope) {
    invoke("playPlaylist", codec.arguments(scope, "playlistId", playlistId))
  }

  override fun startAction(action: VehicleHomeAction) {
    val method = when (action) {
      VehicleHomeAction.LIBRARY_SHUFFLE -> "startLibraryShuffle"
      VehicleHomeAction.LIKED_SHUFFLE -> "startLikedShuffle"
      VehicleHomeAction.CUSTOM_SHUFFLE -> "startCustomShuffle"
    }

    invoke(method)
  }

  override fun handleCall(call: MethodCall, result: MethodChannel.Result) {
    val values = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()

    when (call.method) {
      "authState" -> {
        media.updateAuthorization(values["authorized"] as? Boolean ?: false)
        result.success(true)
      }
      "carPlayState" -> {
        media.updateSourceState(
          serverAvailable = values["serverAvailable"] as? Boolean ?: false,
          localAvailable = values["localAvailable"] as? Boolean ?: false,
          hasAnySource = values["hasAnySource"] as? Boolean ?: false
        )
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  private fun loadEntries(method: String, arguments: Any?, completion: (VehicleBrowseResult) -> Unit) {
    request(method, arguments, codec::decodeEntries, codec::failure, completion)
  }
}
