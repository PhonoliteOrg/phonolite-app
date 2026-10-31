package com.phonoliteorg.phonolite_app.infrastructure.flutter

import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleHomeAction
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleLibraryStatus
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleScope

interface VehicleClient {
  fun loadLibraryStatus(scope: VehicleScope, completion: (VehicleLibraryStatus) -> Unit)
  fun loadHomeActions(completion: (VehicleBrowseResult) -> Unit)
  fun loadArtists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit)
  fun loadPlaylists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit)
  fun loadAlbums(artistId: String, scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit)
  fun playLiked(scope: VehicleScope)
  fun playAlbum(albumId: String, scope: VehicleScope)
  fun playPlaylist(playlistId: String, scope: VehicleScope)
  fun startAction(action: VehicleHomeAction)
}
