import Foundation
import XCTest

import Flutter

@testable import Runner

final class CarPlayContractTests: XCTestCase {
  func testSourceStatePreservesExternalFlagAndAvailableSourceNormalization() {
    XCTAssertEqual(CarPlayCodec.decodeSourceState(nil), .empty)

    let available = CarPlayCodec.decodeSourceState([
      "serverAvailable": false,
      "localAvailable": true,
      "hasAnySource": false,
    ])

    XCTAssertFalse(available.serverAvailable)
    XCTAssertTrue(available.localAvailable)
    XCTAssertTrue(available.hasAnySource)

    let explicit = CarPlayCodec.decodeSourceState(["hasAnySource": true])

    XCTAssertFalse(explicit.serverAvailable)
    XCTAssertFalse(explicit.localAvailable)
    XCTAssertTrue(explicit.hasAnySource)
  }

  func testListCodecPreservesDefaultsMetadataAndMalformedEntryFiltering() {
    let rawItems: [[String: Any]] = [
      ["id": "artist", "title": "Artist"],
      [
        "id": "disabled", "title": "Offline", "subtitle": "Detail", "enabled": false,
        "artworkUrl": "file:///cover.png", "token": "token", "serverPin": "pin",
      ],
      ["id": "", "title": "Missing ID"],
      ["id": "missing-title"],
      ["id": "whitespace", "title": " "],
    ]
    let payload: [String: Any] = ["error": "", "items": rawItems]
    let result = CarPlayCodec.decodeList(payload)

    XCTAssertEqual(result.error, "")
    XCTAssertEqual(result.items.map { $0.id }, ["artist", "disabled", "whitespace"])
    XCTAssertTrue(result.items[0].enabled)
    XCTAssertNil(result.items[0].subtitle)
    XCTAssertFalse(result.items[1].enabled)
    XCTAssertEqual(result.items[1].subtitle, "Detail")
    XCTAssertEqual(result.items[1].artworkURL, "file:///cover.png")
    XCTAssertEqual(result.items[1].token, "token")
    XCTAssertEqual(result.items[1].serverPin, "pin")
    XCTAssertEqual(result.items[2].title, " ")
  }

  func testListErrorsPreserveMessageAndFallbacks() {
    XCTAssertEqual(CarPlayCodec.decodeList(nil).error, "bad_response")
    XCTAssertEqual(CarPlayCodec.decodeList(FlutterError(code: "test", message: nil, details: nil)).error, "error")
    XCTAssertEqual(
      CarPlayCodec.decodeList(FlutterError(code: "test", message: "Unavailable", details: nil)).error,
      "Unavailable"
    )
    XCTAssertTrue(CarPlayCodec.decodeList(["error": "offline"]).items.isEmpty)
    XCTAssertEqual(CarPlayCodec.decodeList(["error": "offline"]).error, "offline")
  }

  func testRequestsKeepExistingMethodNamesScopeAndIdentifierKeys() {
    let cases: [(CarPlayListRequest, String, [String: String])] = [
      (.artists(scope: .local), "getArtists", ["scope": "local"]),
      (.artists(scope: .server), "getArtists", ["scope": "server"]),
      (.albums(scope: .local, artistID: "artist"), "getAlbums", ["scope": "local", "artistId": "artist"]),
      (.playlists(scope: .server), "getPlaylists", ["scope": "server"]),
    ]

    for (request, method, arguments) in cases {
      XCTAssertEqual(CarPlayCodec.method(for: request), method)
      XCTAssertEqual(CarPlayCodec.arguments(for: request) as NSDictionary, arguments as NSDictionary)
    }

    XCTAssertEqual(CarPlayCodec.stateMethod, "getCarPlayState")
  }

  func testPlaybackCommandsKeepImmediateTypedWireMapping() {
    let cases: [(CarPlayCommand, String, [String: String])] = [
      (.playLiked(scope: .local), "playLiked", ["scope": "local"]),
      (.startLibraryShuffle(scope: .server), "startShuffle", ["scope": "server", "kind": "library"]),
      (.playAlbum(scope: .server, albumID: "album"), "playAlbum", ["scope": "server", "albumId": "album"]),
      (.playPlaylist(scope: .local, playlistID: "mix"), "playPlaylist", ["scope": "local", "playlistId": "mix"]),
    ]

    for (command, method, arguments) in cases {
      XCTAssertEqual(CarPlayCodec.method(for: command), method)
      XCTAssertEqual(CarPlayCodec.arguments(for: command) as NSDictionary, arguments as NSDictionary)
    }
  }

  func testStackedPageRequestsCompleteIndependentlyInReplyOrder() {
    let client = CarPlayTestClient()
    let controller = CarPlayBrowseController(client: client)
    let artists = expectation(description: "artists reply")
    let albums = expectation(description: "albums reply")
    var order: [String] = []

    controller.load(.artists(scope: .server)) { _ in
      order.append("artists")
      artists.fulfill()
    }
    controller.load(.albums(scope: .server, artistID: "artist")) { _ in
      order.append("albums")
      albums.fulfill()
    }

    XCTAssertTrue(controller.isLoading)

    client.listReplies[1](CarPlayListResult(items: [], error: nil))
    client.listReplies[0](CarPlayListResult(items: [], error: nil))
    wait(for: [artists, albums], timeout: 1)

    XCTAssertEqual(order, ["albums", "artists"])
    XCTAssertFalse(controller.isLoading)
  }

  func testDisconnectInvalidatesAlreadyQueuedRepliesWithoutCancellingANewRequest() {
    let client = CarPlayTestClient()
    let controller = CarPlayBrowseController(client: client)
    let obsolete = expectation(description: "disconnected reply is ignored")
    obsolete.isInverted = true
    let current = expectation(description: "new scene request")

    controller.load(.artists(scope: .server)) { _ in obsolete.fulfill() }

    client.listReplies[0](CarPlayListResult(items: [], error: nil))

    XCTAssertTrue(controller.updateSourceState(
      CarPlaySourceState(serverAvailable: true, localAvailable: false),
      force: false
    ))
    controller.disconnect()

    XCTAssertFalse(controller.isLoading)
    XCTAssertEqual(controller.sourceState, .empty)

    controller.load(.playlists(scope: .local)) { _ in current.fulfill() }
    client.listReplies[1](CarPlayListResult(items: [], error: nil))
    wait(for: [current, obsolete], timeout: 0.1)

    XCTAssertFalse(controller.isLoading)
  }

  func testStateRepliesAndForcedRefreshUseTheSameSceneRequestBoundary() {
    let client = CarPlayTestClient()
    let controller = CarPlayBrowseController(client: client)
    let obsolete = expectation(description: "old state reply is ignored")
    obsolete.isInverted = true

    controller.requestState { _ in obsolete.fulfill() }
    controller.disconnect()

    client.stateReply?(CarPlaySourceState(serverAvailable: true, localAvailable: false))
    wait(for: [obsolete], timeout: 0.1)

    XCTAssertFalse(controller.updateSourceState(.empty, force: false))
    XCTAssertTrue(controller.updateSourceState(.empty, force: true))
    controller.perform(.playLiked(scope: .local))

    XCTAssertEqual(client.sentCommands.count, 1)
  }
}

private final class CarPlayTestClient: CarPlayClient {
  private(set) var stateReply: ((CarPlaySourceState) -> Void)?
  private(set) var listReplies: [(CarPlayListResult) -> Void] = []
  private(set) var sentCommands: [CarPlayCommand] = []

  func requestState(completion: @escaping (CarPlaySourceState) -> Void) {
    stateReply = completion
  }

  func requestList(_ request: CarPlayListRequest, completion: @escaping (CarPlayListResult) -> Void) {
    listReplies.append(completion)
  }

  func send(_ command: CarPlayCommand) {
    sentCommands.append(command)
  }
}
