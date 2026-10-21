package com.example.phonolite_app.application.controllers.vehicle

import com.example.phonolite_app.data.models.playback.SourceAvailability
import com.example.phonolite_app.data.models.vehicle.VehicleBrowseNode
import com.example.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.example.phonolite_app.data.models.vehicle.VehicleCategory
import com.example.phonolite_app.data.models.vehicle.VehicleHomeAction
import com.example.phonolite_app.data.models.vehicle.VehicleMediaIds
import com.example.phonolite_app.data.models.vehicle.VehicleMessageKind
import com.example.phonolite_app.data.models.vehicle.VehicleScope
import com.example.phonolite_app.infrastructure.flutter.VehicleClient
import java.util.concurrent.atomic.AtomicBoolean

// Requests and callbacks run on the platform main thread; each detached browse request receives one result.
class VehicleBrowseController(
  private val client: VehicleClient,
  private val sourceAvailability: () -> SourceAvailability
) {
  fun loadChildren(parentId: String, completion: (List<VehicleBrowseNode>) -> Unit) {
    val completed = AtomicBoolean(false)
    val completeOnce: (List<VehicleBrowseNode>) -> Unit = { nodes ->
      if (completed.compareAndSet(false, true)) {
        completion(nodes)
      }
    }

    when {
      parentId == VehicleMediaIds.ROOT -> loadRoot(completeOnce)
      parentId == VehicleMediaIds.SERVER_ROOT -> loadSource(VehicleScope.SERVER, completeOnce)
      parentId == VehicleMediaIds.LOCAL_ROOT -> loadSource(VehicleScope.LOCAL, completeOnce)
      parentId == VehicleMediaIds.HOME -> loadHomeActions(completeOnce)
      parentId == VehicleMediaIds.ARTISTS -> loadArtists(VehicleScope.SERVER, completeOnce)
      parentId == VehicleMediaIds.LOCAL_ARTISTS -> loadArtists(VehicleScope.LOCAL, completeOnce)
      parentId == VehicleMediaIds.PLAYLISTS -> loadPlaylists(VehicleScope.SERVER, completeOnce)
      parentId == VehicleMediaIds.LOCAL_PLAYLISTS -> loadPlaylists(VehicleScope.LOCAL, completeOnce)
      parentId.startsWith(VehicleMediaIds.ARTIST_PREFIX) -> loadAlbums(
        parentId.removePrefix(VehicleMediaIds.ARTIST_PREFIX),
        VehicleScope.SERVER,
        completeOnce
      )
      parentId.startsWith(VehicleMediaIds.LOCAL_ARTIST_PREFIX) -> loadAlbums(
        parentId.removePrefix(VehicleMediaIds.LOCAL_ARTIST_PREFIX),
        VehicleScope.LOCAL,
        completeOnce
      )
      else -> completeOnce(emptyList())
    }
  }

  fun play(mediaId: String) {
    when {
      mediaId == VehicleMediaIds.LIKED -> client.playLiked(VehicleScope.SERVER)
      mediaId == VehicleMediaIds.LOCAL_LIKED -> client.playLiked(VehicleScope.LOCAL)
      mediaId.startsWith(VehicleMediaIds.ACTION_PREFIX) -> playHomeAction(
        mediaId.removePrefix(VehicleMediaIds.ACTION_PREFIX)
      )
      mediaId.startsWith(VehicleMediaIds.ALBUM_PREFIX) -> client.playAlbum(
        mediaId.removePrefix(VehicleMediaIds.ALBUM_PREFIX),
        VehicleScope.SERVER
      )
      mediaId.startsWith(VehicleMediaIds.LOCAL_ALBUM_PREFIX) -> client.playAlbum(
        mediaId.removePrefix(VehicleMediaIds.LOCAL_ALBUM_PREFIX),
        VehicleScope.LOCAL
      )
      mediaId.startsWith(VehicleMediaIds.PLAYLIST_PREFIX) -> client.playPlaylist(
        mediaId.removePrefix(VehicleMediaIds.PLAYLIST_PREFIX),
        VehicleScope.SERVER
      )
      mediaId.startsWith(VehicleMediaIds.LOCAL_PLAYLIST_PREFIX) -> client.playPlaylist(
        mediaId.removePrefix(VehicleMediaIds.LOCAL_PLAYLIST_PREFIX),
        VehicleScope.LOCAL
      )
    }
  }

  private fun loadRoot(completion: (List<VehicleBrowseNode>) -> Unit) {
    val availability = sourceAvailability()

    if (!availability.serverAvailable && !availability.localAvailable) {
      completion(listOf(VehicleBrowseNode.Message(VehicleMessageKind.NO_SOURCE)))
      return
    }

    val nodes = mutableListOf<VehicleBrowseNode>()

    if (availability.serverAvailable) {
      nodes.add(VehicleBrowseNode.Source(VehicleScope.SERVER))
    }

    if (availability.localAvailable) {
      nodes.add(VehicleBrowseNode.Source(VehicleScope.LOCAL))
    }

    completion(nodes)
  }

  private fun loadSource(scope: VehicleScope, completion: (List<VehicleBrowseNode>) -> Unit) {
    client.loadLibraryStatus(scope) { status ->
      val nodes = mutableListOf<VehicleBrowseNode>()

      if (scope == VehicleScope.SERVER) {
        nodes.add(VehicleBrowseNode.Category(VehicleCategory.HOME, scope))
      }

      nodes.add(VehicleBrowseNode.Category(VehicleCategory.ARTISTS, scope))
      nodes.add(VehicleBrowseNode.Category(VehicleCategory.PLAYLISTS, scope))

      if (status.likedAvailable) {
        nodes.add(VehicleBrowseNode.Category(VehicleCategory.LIKED, scope))
      }

      completion(nodes)
    }
  }

  private fun loadArtists(scope: VehicleScope, completion: (List<VehicleBrowseNode>) -> Unit) {
    loadEntries(VehicleCategory.ARTISTS, scope, completion) { reply -> client.loadArtists(scope, reply) }
  }

  private fun loadHomeActions(completion: (List<VehicleBrowseNode>) -> Unit) {
    loadEntries(VehicleCategory.HOME, VehicleScope.SERVER, completion, client::loadHomeActions)
  }

  private fun loadPlaylists(scope: VehicleScope, completion: (List<VehicleBrowseNode>) -> Unit) {
    loadEntries(VehicleCategory.PLAYLISTS, scope, completion) { reply -> client.loadPlaylists(scope, reply) }
  }

  private fun loadAlbums(artistId: String, scope: VehicleScope, completion: (List<VehicleBrowseNode>) -> Unit) {
    loadEntries(VehicleCategory.ALBUMS, scope, completion) { reply -> client.loadAlbums(artistId, scope, reply) }
  }

  private fun loadEntries(
    category: VehicleCategory,
    scope: VehicleScope,
    completion: (List<VehicleBrowseNode>) -> Unit,
    operation: ((VehicleBrowseResult) -> Unit) -> Unit
  ) {
    operation { result ->
      if (result.error != null) {
        completion(listOf(VehicleBrowseNode.Message(VehicleMessageKind.ERROR, category, result.error)))
        return@operation
      }

      if (result.items.isEmpty()) {
        completion(listOf(VehicleBrowseNode.Message(VehicleMessageKind.EMPTY, category)))
        return@operation
      }

      completion(result.items.map { entry -> VehicleBrowseNode.Entry(entry, category, scope) })
    }
  }

  private fun playHomeAction(actionId: String) {
    val action = when (actionId) {
      "startLibraryShuffle" -> VehicleHomeAction.LIBRARY_SHUFFLE
      "startLikedShuffle" -> VehicleHomeAction.LIKED_SHUFFLE
      "startCustomShuffle" -> VehicleHomeAction.CUSTOM_SHUFFLE
      else -> return
    }

    client.startAction(action)
  }
}
