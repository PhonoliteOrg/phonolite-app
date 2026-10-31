package com.phonoliteorg.phonolite_app.application.controllers.vehicle

import com.phonoliteorg.phonolite_app.data.models.playback.SourceAvailability
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleBrowseNode
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleCategory
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleEntry
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleHomeAction
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleLibraryStatus
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleMediaIds
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleMessageKind
import com.phonoliteorg.phonolite_app.data.models.vehicle.VehicleScope
import com.phonoliteorg.phonolite_app.infrastructure.flutter.VehicleClient

// Dependency-free JVM checks: no Android browser/session, Flutter engine or playback.
object VehicleBrowseControllerTest {
  @JvmStatic
  fun main(args: Array<String>) {
    noSourcesReturnsOneInformativeNode()
    rootPreservesServerBeforeLocalOrdering()
    localOnlyRootDoesNotRequestTheServer()
    sourceRootsKeepTheExistingCategoriesAndLikedAvailability()
    rootUsesCurrentAvailabilityWithoutRequestingLibraryStatus()
    requestsCarryTheSelectedScopeAndArtist()
    errorsAndEmptyResultsRemainDistinct()
    selectionPreservesTypedOperationsAndIgnoresMessages()
    duplicateRepliesCompleteOnlyOnce()

    println("VehicleBrowseController: 9 headless JVM checks passed")
  }

  private fun noSourcesReturnsOneInformativeNode() {
    val fixture = Fixture()
    val result = fixture.load(VehicleMediaIds.ROOT)
    check(result == listOf(VehicleBrowseNode.Message(VehicleMessageKind.NO_SOURCE)))
    check(fixture.client.requests.isEmpty())
    check(fixture.load("unrecognized").isEmpty())
  }

  private fun rootPreservesServerBeforeLocalOrdering() {
    val fixture = Fixture(SourceAvailability(true, true, true))
    fixture.client.likedAvailable = true
    val result = fixture.load(VehicleMediaIds.ROOT)

    check(fixture.client.requests.isEmpty())
    check(result.size <= 2)
    check(
      result == listOf(
        VehicleBrowseNode.Source(VehicleScope.SERVER),
        VehicleBrowseNode.Source(VehicleScope.LOCAL)
      )
    )
  }

  private fun localOnlyRootDoesNotRequestTheServer() {
    val fixture = Fixture(SourceAvailability(false, true, true))
    val result = fixture.load(VehicleMediaIds.ROOT)
    check(fixture.client.requests.isEmpty())
    check(
      result == listOf(
        VehicleBrowseNode.Source(VehicleScope.LOCAL)
      )
    )
  }

  private fun sourceRootsKeepTheExistingCategoriesAndLikedAvailability() {
    val fixture = Fixture(SourceAvailability(true, true, true))
    fixture.client.likedAvailable = true
    val server = fixture.load(VehicleMediaIds.SERVER_ROOT)
    val local = fixture.load(VehicleMediaIds.LOCAL_ROOT)

    check(fixture.client.requests == listOf("status:SERVER", "status:LOCAL"))
    check(server.size == 4 && local.size == 3)
    check(
      server == listOf(
        VehicleBrowseNode.Category(VehicleCategory.HOME, VehicleScope.SERVER),
        VehicleBrowseNode.Category(VehicleCategory.ARTISTS, VehicleScope.SERVER),
        VehicleBrowseNode.Category(VehicleCategory.PLAYLISTS, VehicleScope.SERVER),
        VehicleBrowseNode.Category(VehicleCategory.LIKED, VehicleScope.SERVER)
      )
    )
    check(
      local == listOf(
        VehicleBrowseNode.Category(VehicleCategory.ARTISTS, VehicleScope.LOCAL),
        VehicleBrowseNode.Category(VehicleCategory.PLAYLISTS, VehicleScope.LOCAL),
        VehicleBrowseNode.Category(VehicleCategory.LIKED, VehicleScope.LOCAL)
      )
    )

    fixture.client.likedAvailable = false
    check(fixture.load(VehicleMediaIds.SERVER_ROOT) == server.dropLast(1))
    check(fixture.load(VehicleMediaIds.LOCAL_ROOT) == local.dropLast(1))
  }

  private fun rootUsesCurrentAvailabilityWithoutRequestingLibraryStatus() {
    val fixture = Fixture(SourceAvailability(true, false, true))
    check(fixture.load(VehicleMediaIds.ROOT) == listOf(VehicleBrowseNode.Source(VehicleScope.SERVER)))

    fixture.availability = SourceAvailability(false, true, true)
    check(fixture.load(VehicleMediaIds.ROOT) == listOf(VehicleBrowseNode.Source(VehicleScope.LOCAL)))

    fixture.availability = SourceAvailability(false, false, true)
    check(fixture.load(VehicleMediaIds.ROOT) == listOf(VehicleBrowseNode.Message(VehicleMessageKind.NO_SOURCE)))
    check(fixture.client.requests.isEmpty())
  }

  private fun requestsCarryTheSelectedScopeAndArtist() {
    val fixture = Fixture()
    fixture.client.entries = VehicleBrowseResult(listOf(VehicleEntry("one", "One", null, false)))
    val artists = fixture.load(VehicleMediaIds.LOCAL_ARTISTS)
    fixture.load(VehicleMediaIds.ARTISTS)
    fixture.load(VehicleMediaIds.PLAYLISTS)
    fixture.load(VehicleMediaIds.LOCAL_PLAYLISTS)
    fixture.load("${VehicleMediaIds.ARTIST_PREFIX}artist-one")
    fixture.load("${VehicleMediaIds.LOCAL_ARTIST_PREFIX}artist-two")
    fixture.load(VehicleMediaIds.HOME)

    check(
      fixture.client.requests == listOf(
        "artists:LOCAL",
        "artists:SERVER",
        "playlists:SERVER",
        "playlists:LOCAL",
        "albums:artist-one:SERVER",
        "albums:artist-two:LOCAL",
        "home"
      )
    )
    check(
      artists == listOf(
        VehicleBrowseNode.Entry(VehicleEntry("one", "One", null, false), VehicleCategory.ARTISTS, VehicleScope.LOCAL)
      )
    )
  }

  private fun errorsAndEmptyResultsRemainDistinct() {
    val fixture = Fixture()
    check(
      fixture.load(VehicleMediaIds.ARTISTS) == listOf(
        VehicleBrowseNode.Message(VehicleMessageKind.EMPTY, VehicleCategory.ARTISTS)
      )
    )

    fixture.client.entries = VehicleBrowseResult(error = "Disconnected")
    check(
      fixture.load(VehicleMediaIds.LOCAL_PLAYLISTS) == listOf(
        VehicleBrowseNode.Message(VehicleMessageKind.ERROR, VehicleCategory.PLAYLISTS, "Disconnected")
      )
    )
  }

  private fun selectionPreservesTypedOperationsAndIgnoresMessages() {
    val fixture = Fixture()
    listOf(
      "liked", "local_liked", "album:album-one", "local_album:album-two",
      "playlist:list-one", "local_playlist:list-two", "action:startLibraryShuffle",
      "action:startLikedShuffle", "action:startCustomShuffle", "message:disabled", "action:unknown", "unknown"
    ).forEach(fixture.controller::play)

    check(
      fixture.client.actions == listOf(
        "liked:SERVER", "liked:LOCAL", "album:album-one:SERVER", "album:album-two:LOCAL",
        "playlist:list-one:SERVER", "playlist:list-two:LOCAL", "action:LIBRARY_SHUFFLE",
        "action:LIKED_SHUFFLE", "action:CUSTOM_SHUFFLE"
      )
    )
  }

  private fun duplicateRepliesCompleteOnlyOnce() {
    val fixture = Fixture()
    fixture.client.repeatEntryReply = true
    var completions = 0
    fixture.controller.loadChildren(VehicleMediaIds.ARTISTS) { completions += 1 }
    check(completions == 1)
  }

  private class Fixture(var availability: SourceAvailability = SourceAvailability()) {
    val client = Client()
    val controller = VehicleBrowseController(client) { availability }

    fun load(parentId: String): List<VehicleBrowseNode> {
      var result: List<VehicleBrowseNode>? = null
      controller.loadChildren(parentId) { nodes -> result = nodes }

      return checkNotNull(result)
    }
  }

  private class Client : VehicleClient {
    val requests = mutableListOf<String>()
    val actions = mutableListOf<String>()
    var entries = VehicleBrowseResult()
    var likedAvailable = false
    var repeatEntryReply = false

    override fun loadLibraryStatus(scope: VehicleScope, completion: (VehicleLibraryStatus) -> Unit) {
      requests.add("status:$scope")
      completion(VehicleLibraryStatus(likedAvailable))
    }

    override fun loadHomeActions(completion: (VehicleBrowseResult) -> Unit) = reply("home", completion)

    override fun loadArtists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
      reply("artists:$scope", completion)
    }

    override fun loadPlaylists(scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
      reply("playlists:$scope", completion)
    }

    override fun loadAlbums(artistId: String, scope: VehicleScope, completion: (VehicleBrowseResult) -> Unit) {
      reply("albums:$artistId:$scope", completion)
    }

    override fun playLiked(scope: VehicleScope) {
      actions.add("liked:$scope")
    }

    override fun playAlbum(albumId: String, scope: VehicleScope) {
      actions.add("album:$albumId:$scope")
    }

    override fun playPlaylist(playlistId: String, scope: VehicleScope) {
      actions.add("playlist:$playlistId:$scope")
    }

    override fun startAction(action: VehicleHomeAction) {
      actions.add("action:$action")
    }

    private fun reply(request: String, completion: (VehicleBrowseResult) -> Unit) {
      requests.add(request)
      completion(entries)

      if (repeatEntryReply) {
        completion(entries)
      }
    }
  }
}
