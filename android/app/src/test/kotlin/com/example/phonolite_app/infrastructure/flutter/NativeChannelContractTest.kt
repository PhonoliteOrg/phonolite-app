package com.example.phonolite_app.infrastructure.flutter

import com.example.phonolite_app.application.controllers.media.NativeMediaController
import com.example.phonolite_app.data.models.audio.OutputDevice
import com.example.phonolite_app.data.models.playback.NativeRemoteCommand
import com.example.phonolite_app.data.models.vehicle.VehicleBrowseResult
import com.example.phonolite_app.data.models.vehicle.VehicleHomeAction
import com.example.phonolite_app.data.models.vehicle.VehicleScope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Dependency-free local JVM contracts. No Android objects, Flutter engine or real audio are started.
object NativeChannelContractTest {
  @JvmStatic
  fun main(arguments: Array<String>) {
    metadataDecoding()
    metadataDispatchAndCompletion()
    remoteCommandEncoding()
    vehicleRequestScopes()
    vehicleResponsesAndFailures()
    sourceStateDecoding()
    attachmentAndReleasedRequests()
    audioBoundaryValues()

    println("8 native channel contract checks passed")
  }

  private fun mediaController(): NativeMediaController = NativeMediaController({}, {}, {})

  private fun metadataDecoding() {
    val codec = NowPlayingCodec()
    val artwork = byteArrayOf(1, 2, 3)
    val state = codec.decode(
      mapOf(
        "epoch" to 3L,
        "trackId" to 4,
        "duration" to "1.2346",
        "position" to -2,
        "isPlaying" to "TRUE",
        "liked" to 1,
        "artworkBytes" to artwork
      )
    )

    check(state.epoch == 3 && state.trackId == "4")
    check(state.durationMs == 1235L && state.positionMs == 0L)
    check(state.isPlaying && state.liked && state.artworkBytes === artwork)
    check(codec.decode(null).title.isEmpty())
    check(codec.decode(mapOf("duration" to Double.NaN)).durationMs == 0L)
    check(codec.decode(mapOf("position" to Double.POSITIVE_INFINITY)).positionMs == 0L)
    check(!codec.decode(mapOf("isPlaying" to "yes", "liked" to "0")).isPlaying)
  }

  private fun metadataDispatchAndCompletion() {
    val media = mediaController()
    val endpoint = FakeEndpoint()
    val adapter = NowPlayingChannelAdapter(endpoint, { it() }, media)
    adapter.attach()

    val published = endpoint.call("setNowPlaying", mapOf("trackId" to "a", "position" to 10))
    check(published.count == 1 && published.value == true)
    check(media.latestState?.positionMs == 10_000L)

    endpoint.call("setNowPlaying", mapOf("trackId" to "a", "position" to 1))
    check(media.latestState?.positionMs == 10_000L)

    val cleared = endpoint.call("clearNowPlaying")
    check(cleared.count == 1 && cleared.value == true && media.latestState == null)
    check(endpoint.call("unknown").notImplemented)
  }

  private fun remoteCommandEncoding() {
    val endpoint = FakeEndpoint()
    val adapter = NowPlayingChannelAdapter(endpoint, { it() }, mediaController())
    adapter.attach()

    val commands = listOf(
      NativeRemoteCommand.Play to "play",
      NativeRemoteCommand.Pause to "pause",
      NativeRemoteCommand.Next to "next",
      NativeRemoteCommand.Previous to "prev",
      NativeRemoteCommand.ToggleLike to "toggleLike"
    )
    for ((command, type) in commands) {
      adapter.sendRemoteCommand(command)
      check(endpoint.last().method == "remoteCommand")
      check(endpoint.last().arguments == mapOf("type" to type))
    }

    adapter.sendRemoteCommand(NativeRemoteCommand.Seek(2.5))
    check(endpoint.last().arguments == mapOf("type" to "seek", "position" to 2.5))
  }

  private fun vehicleRequestScopes() {
    val endpoint = FakeEndpoint()
    val adapter = VehicleChannelAdapter(endpoint, { it() }, mediaController())
    adapter.attach()

    adapter.loadArtists(VehicleScope.SERVER) {}
    check(endpoint.last().method == "getArtists" && endpoint.last().arguments == null)
    adapter.loadPlaylists(VehicleScope.LOCAL) {}
    check(endpoint.last().method == "getPlaylists" && endpoint.last().arguments == mapOf("scope" to "local"))
    adapter.loadAlbums("artist", VehicleScope.LOCAL) {}
    check(endpoint.last().arguments == mapOf("scope" to "local", "artistId" to "artist"))
    adapter.playLiked(VehicleScope.LOCAL)
    check(endpoint.last().method == "playLiked" && endpoint.last().arguments == mapOf("scope" to "local"))
    adapter.playAlbum("album", VehicleScope.SERVER)
    check(endpoint.last().method == "playAlbum" && endpoint.last().arguments == mapOf("albumId" to "album"))
    adapter.playPlaylist("playlist", VehicleScope.LOCAL)
    check(endpoint.last().arguments == mapOf("scope" to "local", "playlistId" to "playlist"))
    adapter.startAction(VehicleHomeAction.CUSTOM_SHUFFLE)
    check(endpoint.last().method == "startCustomShuffle" && endpoint.last().arguments == null)
  }

  private fun vehicleResponsesAndFailures() {
    val endpoint = FakeEndpoint()
    val adapter = VehicleChannelAdapter(endpoint, { it() }, mediaController())
    adapter.attach()
    var result: VehicleBrowseResult? = null

    adapter.loadHomeActions { result = it }
    endpoint.last().result!!.success(
      mapOf(
        "items" to listOf(
          null,
          "bad",
          mapOf("id" to "", "title" to "missing"),
          mapOf("id" to 12, "title" to "valid", "enabled" to false)
        )
      )
    )
    check(result!!.items.single().id == "12" && !result!!.items.single().enabled)

    adapter.loadHomeActions { result = it }
    endpoint.last().result!!.notImplemented()
    check(result!!.error == "Phonolite is still loading")

    adapter.loadHomeActions { result = it }
    endpoint.last().result!!.error("failure", null, null)
    check(result!!.error == "failure")

    adapter.loadHomeActions { result = it }
    endpoint.last().result!!.success("invalid")
    check(result!!.error == "Unavailable")

    var liked: Boolean? = null
    adapter.loadLibraryStatus(VehicleScope.SERVER) { liked = it.likedAvailable }
    endpoint.last().result!!.error("failure", "detail", null)
    check(liked == false)
  }

  private fun sourceStateDecoding() {
    val media = mediaController()
    val endpoint = FakeEndpoint()
    val adapter = VehicleChannelAdapter(endpoint, { it() }, media)
    adapter.attach()

    val result = endpoint.call("carPlayState", mapOf("localAvailable" to true, "hasAnySource" to false))
    check(result.count == 1 && result.value == true)
    check(media.availability.localAvailable && media.availability.hasAnySource && !media.authorized)
    endpoint.call("authState", mapOf("authorized" to true))
    check(media.authorized && media.availability.localAvailable)
    endpoint.call("authState", mapOf("authorized" to "true"))
    check(!media.authorized && media.availability.hasAnySource)
    check(endpoint.call("unknown").notImplemented)
  }

  private fun attachmentAndReleasedRequests() {
    val pending = mutableListOf<() -> Unit>()
    val endpoint = FakeEndpoint()
    val adapter = VehicleChannelAdapter(endpoint, { pending.add(it) }, mediaController())
    adapter.attach()
    adapter.attach()
    check(endpoint.attachments == 1)

    var callbacks = 0
    adapter.loadHomeActions {
      callbacks++
      check(it.error == "Phonolite is still loading")
    }
    adapter.detach()
    adapter.detach()
    check(endpoint.detachments == 1 && endpoint.incomingHandler == null)
    pending.single()()
    check(callbacks == 1 && endpoint.invocations.isEmpty())

    adapter.attach()
    check(endpoint.attachments == 2)
  }

  private fun audioBoundaryValues() {
    val codec = AudioOutputCodec()
    check(codec.configuration(null) == null)
    check(codec.configuration(mapOf("sampleRate" to "48000", "channels" to 2)) == null)
    val configuration = codec.configuration(mapOf("sampleRate" to 48_000L, "channels" to 2))!!
    check(configuration.sampleRate == 48_000 && configuration.channels == 2 && configuration.deviceId == -1)
    check(codec.id(mapOf("id" to 5L)) == 5)
    check(
      codec.encodeDevices(listOf(OutputDevice(-1, "System Default"))) ==
        listOf(mapOf("id" to -1, "name" to "System Default"))
    )
  }

  private class Reply : MethodChannel.Result {
    var count = 0
    var value: Any? = null
    var notImplemented = false

    override fun success(result: Any?) {
      count++
      value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
      error("Unexpected error: $errorCode")
    }

    override fun notImplemented() {
      count++
      notImplemented = true
    }
  }

  private class FakeEndpoint : FlutterChannelEndpoint {
    var incomingHandler: ((MethodCall, MethodChannel.Result) -> Unit)? = null
    var attachments = 0
    var detachments = 0
    val invocations = mutableListOf<Invocation>()

    override fun setHandler(handler: ((MethodCall, MethodChannel.Result) -> Unit)?) {
      incomingHandler = handler
      if (handler == null) detachments++ else attachments++
    }

    override fun invoke(method: String, arguments: Any?, result: MethodChannel.Result?) {
      invocations.add(Invocation(method, arguments, result))
    }

    fun call(method: String, arguments: Any? = null): Reply {
      val reply = Reply()
      checkNotNull(incomingHandler)(MethodCall(method, arguments), reply)
      check(reply.count == 1)

      return reply
    }

    fun last(): Invocation = invocations.last()
  }

  private data class Invocation(val method: String, val arguments: Any?, val result: MethodChannel.Result?)
}
