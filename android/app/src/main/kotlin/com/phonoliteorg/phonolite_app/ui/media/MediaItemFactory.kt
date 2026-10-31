package com.phonoliteorg.phonolite_app.ui.media

import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleBrowseNode
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleCategory
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleMediaIds
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleMessageKind
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleScope

class MediaItemFactory {
  private fun buildSource(node: VehicleBrowseNode.Source): MediaBrowserCompat.MediaItem {
    if (node.scope == VehicleScope.LOCAL) {
      return item(VehicleMediaIds.LOCAL_ROOT, "Local Library", "Browse downloaded music", browsable = true)
    }

    return item(VehicleMediaIds.SERVER_ROOT, "Server Library", "Browse your server library", browsable = true)
  }

  private fun buildCategory(node: VehicleBrowseNode.Category): MediaBrowserCompat.MediaItem {
    val local = node.scope == VehicleScope.LOCAL

    return when (node.kind) {
      VehicleCategory.HOME -> item(VehicleMediaIds.HOME, "Home", "Shuffle actions", browsable = true)
      VehicleCategory.ARTISTS -> item(
        if (local) VehicleMediaIds.LOCAL_ARTISTS else VehicleMediaIds.ARTISTS,
        if (local) "Local Artists" else "Artists",
        if (local) "Browse downloaded artists" else "Browse by artist",
        browsable = true
      )
      VehicleCategory.PLAYLISTS -> item(
        if (local) VehicleMediaIds.LOCAL_PLAYLISTS else VehicleMediaIds.PLAYLISTS,
        if (local) "Local Playlists" else "Playlists",
        if (local) "Browse local playlists" else "Browse playlists",
        browsable = true
      )
      VehicleCategory.LIKED -> item(
        if (local) VehicleMediaIds.LOCAL_LIKED else VehicleMediaIds.LIKED,
        if (local) "Local Liked Songs" else "Liked Songs",
        "Play from the top"
      )
      VehicleCategory.ALBUMS -> error("Album entries require an artist's browse result")
    }
  }

  private fun buildEntry(node: VehicleBrowseNode.Entry): MediaBrowserCompat.MediaItem {
    val entry = node.entry
    val local = node.scope == VehicleScope.LOCAL
    val browsable = node.kind == VehicleCategory.ARTISTS
    val prefix = when (node.kind) {
      VehicleCategory.HOME -> VehicleMediaIds.ACTION_PREFIX
      VehicleCategory.ARTISTS -> if (local) VehicleMediaIds.LOCAL_ARTIST_PREFIX else VehicleMediaIds.ARTIST_PREFIX
      VehicleCategory.PLAYLISTS -> if (local) VehicleMediaIds.LOCAL_PLAYLIST_PREFIX else VehicleMediaIds.PLAYLIST_PREFIX
      VehicleCategory.ALBUMS -> if (local) VehicleMediaIds.LOCAL_ALBUM_PREFIX else VehicleMediaIds.ALBUM_PREFIX
      VehicleCategory.LIKED -> VehicleMediaIds.MESSAGE_PREFIX
    }
    val mediaId = if (entry.enabled || browsable) {
      "$prefix${entry.id}"
    } else {
      "${VehicleMediaIds.MESSAGE_PREFIX}${entry.id}"
    }

    return item(mediaId, entry.title, entry.subtitle, browsable)
  }

  private fun buildMessage(node: VehicleBrowseNode.Message): MediaBrowserCompat.MediaItem {
    if (node.kind == VehicleMessageKind.NO_SOURCE) {
      return item(
        "${VehicleMediaIds.MESSAGE_PREFIX}no_source",
        "No available library",
        "Connect to a server or download tracks in Phonolite",
        browsable = true
      )
    }

    val operation = when (node.category) {
      VehicleCategory.HOME -> "getHomeActions"
      VehicleCategory.ARTISTS -> "getArtists"
      VehicleCategory.PLAYLISTS -> "getPlaylists"
      VehicleCategory.ALBUMS -> "getAlbums"
      else -> ""
    }

    if (node.kind == VehicleMessageKind.ERROR) {
      return item("${VehicleMediaIds.MESSAGE_PREFIX}${operation}_error", "Phonolite", node.error)
    }

    return item(
      "${VehicleMediaIds.MESSAGE_PREFIX}${operation}_empty",
      "Nothing here yet",
      "Open Phonolite on your phone for more options"
    )
  }

  private fun item(
    mediaId: String,
    title: String,
    subtitle: String?,
    browsable: Boolean = false
  ): MediaBrowserCompat.MediaItem {
    val description = MediaDescriptionCompat.Builder()
      .setMediaId(mediaId)
      .setTitle(title)
      .setSubtitle(subtitle)
      .build()
    val flags = if (browsable) {
      MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
    } else {
      MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
    }

    return MediaBrowserCompat.MediaItem(description, flags)
  }

  fun build(node: VehicleBrowseNode): MediaBrowserCompat.MediaItem = when (node) {
    is VehicleBrowseNode.Source -> buildSource(node)
    is VehicleBrowseNode.Category -> buildCategory(node)
    is VehicleBrowseNode.Entry -> buildEntry(node)
    is VehicleBrowseNode.Message -> buildMessage(node)
  }
}
