import Foundation
import XCTest

import Flutter

@testable import Runner

final class NowPlayingContractTests: XCTestCase {
  func testMissingAndNullMetadataFieldsRetainPreviousValues() {
    var state = NowPlayingState()

    state.apply(NowPlayingCodec.decode([
      "trackId": "track-a",
      "epoch": 2,
      "title": "Track A",
      "artist": "Artist A",
      "album": "Album A",
      "duration": 200.0,
      "position": 12.0,
      "isPlaying": true,
      "liked": true,
    ]))

    state.apply(NowPlayingCodec.decode([
      "trackId": NSNull(),
      "epoch": NSNull(),
      "title": NSNull(),
      "artist": NSNull(),
      "album": NSNull(),
      "duration": NSNull(),
      "position": 13.0,
      "isPlaying": NSNull(),
      "liked": false,
    ]))

    XCTAssertEqual(state.trackID, "track-a")
    XCTAssertEqual(state.epoch, 2)
    XCTAssertEqual(state.title, "Track A")
    XCTAssertEqual(state.artist, "Artist A")
    XCTAssertEqual(state.album, "Album A")
    XCTAssertEqual(state.duration, 200)
    XCTAssertEqual(state.position, 13)
    XCTAssertTrue(state.isPlaying)
    XCTAssertFalse(state.liked)
  }

  func testArtworkFieldsAreNormalizedAndMissingIdentityIsReplaced() {
    let bytes = Data([1, 2, 3])
    let update = NowPlayingCodec.decode([
      "artworkKey": " album-a ",
      "artworkUrl": " https://server.test/cover ",
      "artworkPath": " /local/cover ",
      "token": " secret ",
      "serverPin": " pin ",
      "artworkBytes": FlutterStandardTypedData(bytes: bytes),
    ])

    XCTAssertEqual(update.artworkSource, ArtworkSource(
      key: "album-a",
      url: "https://server.test/cover",
      path: "/local/cover",
      token: "secret",
      serverPin: "pin"
    ))
    XCTAssertEqual(update.artworkData, bytes)

    let missing = NowPlayingCodec.decode(["position": 3.0])

    XCTAssertEqual(missing.artworkSource, ArtworkSource())
    XCTAssertNil(missing.artworkData)

    let malformed = NowPlayingCodec.decode([
      "artworkKey": " \n ",
      "artworkUrl": NSNumber(value: 1),
      "artworkPath": NSNull(),
      "token": " ",
      "serverPin": NSNull(),
      "artworkBytes": bytes,
    ])

    XCTAssertEqual(malformed.artworkSource, ArtworkSource())
    XCTAssertNil(malformed.artworkData)
  }

  func testPreloadSourcesUseTheSameIdentityNormalizationAndSkipMalformedEntries() {
    let sources = NowPlayingCodec.decodeArtworkSources([
      [
        "artworkKey": " cover ", "artworkUrl": " https://server.test/cover ", "token": " secret ", "serverPin": " pin ",
      ],
      ["artworkKey": " local ", "artworkPath": " /local/cover "],
      ["artworkUrl": " \n "],
      ["artworkPath": 12],
      NSNull(),
      "invalid",
    ])

    XCTAssertEqual(sources, [
      ArtworkSource(key: "cover", url: "https://server.test/cover", token: "secret", serverPin: "pin"),
      ArtworkSource(key: "local", path: "/local/cover"),
    ])
    XCTAssertTrue(NowPlayingCodec.decodeArtworkSources([]).isEmpty)
  }

  func testCodecRetainsNumericBridgingWithoutParsingTextNumbers() {
    let numeric = NowPlayingCodec.decode([
      "isPlaying": NSNumber(value: 1),
      "liked": NSNumber(value: 0),
      "duration": NSNumber(value: 120),
      "position": NSNumber(value: 12.5),
    ])

    XCTAssertEqual(numeric.isPlaying, true)
    XCTAssertEqual(numeric.liked, false)
    XCTAssertEqual(numeric.duration, 120)
    XCTAssertEqual(numeric.position, 12.5)

    let text = NowPlayingCodec.decode([
      "isPlaying": "true",
      "liked": "false",
      "duration": "120",
      "position": "12.5",
    ])

    XCTAssertNil(text.isPlaying)
    XCTAssertNil(text.liked)
    XCTAssertNil(text.duration)
    XCTAssertNil(text.position)
  }

  func testTrackAndSeekEpochResetTheBackwardPositionGate() {
    var state = NowPlayingState()

    state.apply(NowPlayingUpdate(trackID: "track-a", epoch: 1, position: 12))
    state.apply(NowPlayingUpdate(position: 1))

    XCTAssertEqual(state.position, 12)

    state.apply(NowPlayingUpdate(position: 11.25))

    XCTAssertEqual(state.position, 11.25, "The existing 0.75-second tolerance is inclusive")

    state.apply(NowPlayingUpdate(epoch: 2, position: 2))

    XCTAssertEqual(state.position, 2)

    state.apply(NowPlayingUpdate(trackID: "track-b", position: 1))

    XCTAssertEqual(state.position, 1)
  }

  func testInvalidPositionsClampBeforeApplyingTheBackwardGate() {
    for position in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
      var state = NowPlayingState()

      state.apply(NowPlayingUpdate(position: position))

      XCTAssertEqual(state.position, 0)

      state.apply(NowPlayingUpdate(position: 12))
      state.apply(NowPlayingUpdate(position: position))

      XCTAssertEqual(state.position, 12)
    }
  }

  func testArtworkCacheAndSessionIdentityRemainCredentialAndPinScoped() {
    let source = ArtworkSource(key: "album", url: "https://server.test/cover", path: nil, token: "one", serverPin: "a")
    let original = ArtworkCacheKey(source: source)
    let alternatives = [
      ArtworkSource(key: "other", url: source.url, token: source.token, serverPin: source.serverPin),
      ArtworkSource(
        key: source.key, url: "https://server.test/other", token: source.token, serverPin: source.serverPin
      ),
      ArtworkSource(
        key: source.key, url: source.url, path: "/local/cover", token: source.token, serverPin: source.serverPin
      ),
      ArtworkSource(key: source.key, url: source.url, token: "two", serverPin: source.serverPin),
      ArtworkSource(key: source.key, url: source.url, token: source.token, serverPin: "b"),
    ]

    XCTAssertEqual(original, ArtworkCacheKey(source: source))

    for alternative in alternatives {
      XCTAssertNotEqual(original, ArtworkCacheKey(source: alternative))
    }

    let implicitPort = URL(string: "https://SERVER.test/cover")!
    let explicitPort = URL(string: "https://server.test:443/other")!
    let originalSession = ArtworkSessionIdentity(url: implicitPort, serverPin: "a", token: "one")

    XCTAssertEqual(originalSession, ArtworkSessionIdentity(url: explicitPort, serverPin: "a", token: "one"))
    XCTAssertNotEqual(originalSession, ArtworkSessionIdentity(url: explicitPort, serverPin: "a", token: "two"))
    XCTAssertNotEqual(originalSession, ArtworkSessionIdentity(url: explicitPort, serverPin: "b", token: "one"))
  }
}
