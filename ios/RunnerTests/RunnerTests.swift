import Foundation
import MediaPlayer
import UIKit
import XCTest

import Flutter

@testable import Runner

final class RunnerTests: XCTestCase {
  private var coordinator: NowPlayingCoordinator!

  override func setUp() {
    super.setUp()

    coordinator = NowPlayingCoordinator()
  }

  override func tearDown() {
    coordinator.clear()
    coordinator = nil

    super.tearDown()
  }

  func testArtworkSurvivesPositionUpdatesWithoutBeingRecreated() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())

    coordinator.update(NowPlayingCodec.decode(args))

    let first = artwork()

    XCTAssertNotNil(first)

    args["position"] = 15.0

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertTrue(first === artwork())

    let requested = CGSize(width: 10, height: 10)

    XCTAssertEqual(first?.image(at: requested)?.size, requested)
  }

  func testChangingAlbumsClearsThePreviousCover() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertNotNil(artwork())

    coordinator.update(NowPlayingCodec.decode(metadata(key: "album-b")))

    XCTAssertNil(artwork())
  }

  func testConsecutiveTracksInAnAlbumKeepTheArtworkObject() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())

    coordinator.update(NowPlayingCodec.decode(args))

    let first = artwork()

    args["trackId"] = "track-b"
    args["title"] = "Track B"
    args["epoch"] = 2

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertTrue(first === artwork())
    XCTAssertEqual(coordinator.buildNowPlayingInfo()[MPMediaItemPropertyTitle] as? String, "Track B")
  }

  func testReturningToAnAlbumReusesDecodedArtworkWithoutReadingTheFileAgain() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    try imageData().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var args = metadata()
    args["artworkPath"] = url.path

    coordinator.update(NowPlayingCodec.decode(args))
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)

    let first = artwork()

    coordinator.update(NowPlayingCodec.decode(metadata(key: "album-b")))

    XCTAssertNil(artwork())

    try FileManager.default.removeItem(at: url)
    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertTrue(first === artwork())

    coordinator.clear()
    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertNil(artwork(), "Clearing Now Playing must also discard cached covers")
  }

  func testLargeArtworkIsDownsampledBeforePublishing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1

    let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
    }

    try image.pngData()!.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var args = metadata()
    args["artworkPath"] = url.path

    coordinator.update(NowPlayingCodec.decode(args))
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)

    XCTAssertEqual(artwork()?.bounds.size, CGSize(width: 1024, height: 512))
  }

  func testRapidTrackChangeCannotInstallAnEarlierCover() throws {
    let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    try imageData().write(to: first)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1

    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    }

    try image.pngData()!.write(to: second)
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
    }

    var args = metadata()
    args["artworkPath"] = first.path

    coordinator.update(NowPlayingCodec.decode(args))

    args["artworkKey"] = "album-b"
    args["trackId"] = "track-b"
    args["artworkPath"] = second.path

    coordinator.update(NowPlayingCodec.decode(args))
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)

    XCTAssertEqual(artwork()?.bounds.size, image.size)
  }

  func testCorruptBytesDoNotDiscardAValidCover() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())

    coordinator.update(NowPlayingCodec.decode(args))

    let first = artwork()

    args["artworkBytes"] = FlutterStandardTypedData(bytes: Data([0, 1, 2]))

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertTrue(first === artwork())
  }

  func testSeekEpochAllowsPositionToMoveBackward() {
    coordinator.update(NowPlayingCodec.decode(metadata()))

    var args = metadata()
    args["epoch"] = 2
    args["position"] = 2.0

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertEqual(
      coordinator.buildNowPlayingInfo()[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double,
      2.0
    )
  }

  func testOfflineArtworkLoadsWithoutFlutterDecoding() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    try imageData().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var args = metadata()
    args["artworkPath"] = url.path

    coordinator.update(NowPlayingCodec.decode(args))
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)
  }

  func testRemoteArtworkUsesAuthenticationAndRetriesFailedResponses() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkURLProtocol.self]

    let session = URLSession(configuration: configuration)

    defer {
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)

    let png = imageData()
    var attempts = 0

    ArtworkURLProtocol.respond = { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
      attempts += 1

      // Even valid image bytes in an HTTP error response must be rejected.
      return (attempts == 1 ? 503 : 200, png)
    }

    var args = metadata()
    args["artworkUrl"] = "https://artwork.invalid/cover"
    args["token"] = "secret"
    args["serverPin"] = String(repeating: "a", count: 64)

    coordinator.update(NowPlayingCodec.decode(args))
    expectation(for: NSPredicate { [weak self] _, _ in
      guard let self else {
        return false
      }

      // Position updates are what trigger retry in normal playback.
      self.coordinator.update(NowPlayingCodec.decode(args))

      return self.artwork() != nil
    }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)

    XCTAssertEqual(attempts, 2)
  }

  func testRemoteCacheReusesAlbumsAndSeparatesCredentialsAndPins() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkURLProtocol.self]

    let session = URLSession(configuration: configuration)

    defer {
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)

    let png = imageData()
    var requests = 0

    ArtworkURLProtocol.respond = { _ in
      requests += 1

      return (200, png)
    }

    var args = metadata()
    args["artworkUrl"] = "https://artwork.invalid/cover"
    args["token"] = "first-session"
    args["serverPin"] = String(repeating: "a", count: 64)

    let load = {
      self.coordinator.update(NowPlayingCodec.decode(args))
      self.expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
      self.waitForExpectations(timeout: 3)
    }

    load()

    let first = artwork()

    coordinator.update(NowPlayingCodec.decode(metadata(key: "album-b")))
    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertTrue(first === artwork())
    XCTAssertEqual(requests, 1)

    args["token"] = "second-session"
    load()

    XCTAssertEqual(requests, 2)

    args["serverPin"] = String(repeating: "b", count: 64)
    load()

    XCTAssertEqual(requests, 3)
  }

  func testClearInvalidatesPendingLocalArtworkAndCarPlayRefreshStaysEmpty() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    try imageData().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var args = metadata()
    args["artworkPath"] = url.path

    coordinator.update(NowPlayingCodec.decode(args))
    coordinator.clear()
    coordinator.refreshPresentation()

    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)

    // Drain the asynchronous file completion after the clear operation.
    let settled = expectation(description: "artwork completion settled")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
    waitForExpectations(timeout: 3)

    XCTAssertNil(artwork())
    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
  }

  func testClearingKeepsAnInjectedArtworkSessionUsable() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkURLProtocol.self]

    let session = URLSession(configuration: configuration)

    defer {
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)

    let png = imageData()
    var requests = 0

    ArtworkURLProtocol.respond = { _ in
      requests += 1

      return (200, png)
    }

    var args = metadata()
    args["artworkUrl"] = "https://artwork.invalid/cover"
    args["serverPin"] = String(repeating: "a", count: 64)

    func loadArtwork() {
      coordinator.update(NowPlayingCodec.decode(args))
      expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
      waitForExpectations(timeout: 3)
    }

    loadArtwork()
    coordinator.clear()
    loadArtwork()

    XCTAssertEqual(requests, 2)
    XCTAssertNotNil(artwork())
  }

  func testPresentationCallbackReceivesUpdatesRefreshAndClearedState() {
    var states: [NowPlayingState] = []

    coordinator.onPresentationChanged = { states.append($0) }
    coordinator.update(NowPlayingCodec.decode(["trackId": "track-a", "liked": true]))
    coordinator.refreshPresentation()
    coordinator.clear()

    XCTAssertEqual(states.count, 3)
    XCTAssertEqual(states[0].trackID, "track-a")
    XCTAssertTrue(states[0].liked)
    XCTAssertEqual(states[1].trackID, "track-a")
    XCTAssertTrue(states[1].liked)
    XCTAssertNil(states[2].trackID)
    XCTAssertFalse(states[2].liked)
  }

  func testMetadataPatchRetainsPlaybackButMissingArtworkIdentityClearsTheCover() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())

    coordinator.update(NowPlayingCodec.decode(args))

    XCTAssertNotNil(artwork())

    coordinator.update(NowPlayingCodec.decode(["position": 15.0]))

    let info = coordinator.buildNowPlayingInfo()

    XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Track A")
    XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 15)
    XCTAssertTrue(coordinator.isPlaying)
    XCTAssertNil(artwork())
  }

  func testPreloadingDeduplicatesAndBoundsCoversWithoutChangingCurrentPresentation() {
    let session = artworkTestSession()
    defer {
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())
    coordinator.update(NowPlayingCodec.decode(args))
    let original = artwork()
    let png = imageData()
    let warmed = expectation(description: "first two upcoming covers decoded")
    var requests: [String] = []

    ArtworkURLProtocol.respond = { request in
      requests.append(request.url!.lastPathComponent)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")

      // A request starts only after the previous cover has been decoded.
      if requests.count == 3 {
        warmed.fulfill()
      }

      return (200, png)
    }

    coordinator.preloadArtwork([
      artworkSource("b"), artworkSource("b"), artworkSource("c"), artworkSource("d"), artworkSource("e"),
    ])
    wait(for: [warmed], timeout: 3)

    XCTAssertTrue(original === artwork())
    XCTAssertEqual(coordinator.buildNowPlayingInfo()[MPMediaItemPropertyTitle] as? String, "Track A")

    args = metadata(key: "c")
    args["artworkUrl"] = artworkSource("c").url
    args["token"] = "secret"
    args["serverPin"] = String(repeating: "a", count: 64)
    coordinator.update(NowPlayingCodec.decode(args))

    let next = artwork()

    XCTAssertNotNil(next, "Upcoming artwork must be available synchronously at the track change")
    XCTAssertFalse(original === next)
    XCTAssertEqual(requests, ["b", "c", "d"])

    coordinator.refreshPresentation()

    XCTAssertTrue(
      next === MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
      "CarPlay refresh must publish the same prepared artwork"
    )
  }

  func testAnInflightPreloadBecomesCurrentWithoutAnotherRequest() {
    let session = artworkTestSession()
    let release = DispatchSemaphore(value: 0)
    defer {
      release.signal()
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)
    let png = imageData()
    let started = expectation(description: "preload started")
    var requests = 0

    ArtworkURLProtocol.respond = { _ in
      requests += 1

      if requests == 1 {
        started.fulfill()
        _ = release.wait(timeout: .now() + 3)
      }

      return (200, png)
    }

    coordinator.preloadArtwork([artworkSource("b")])
    wait(for: [started], timeout: 3)

    var args = metadata(key: "b")
    args["artworkUrl"] = artworkSource("b").url
    args["token"] = "secret"
    args["serverPin"] = String(repeating: "a", count: 64)
    coordinator.update(NowPlayingCodec.decode(args))
    release.signal()
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)

    XCTAssertEqual(requests, 1)
  }

  func testCurrentArtworkPreemptsASlowPreloadAndRejectsItsLateCover() throws {
    let session = artworkTestSession()
    let release = DispatchSemaphore(value: 0)
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    }

    try image.pngData()!.write(to: local)
    defer {
      release.signal()
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
      try? FileManager.default.removeItem(at: local)
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)
    let png = imageData()
    let started = expectation(description: "slow preload started")
    let completed = expectation(description: "obsolete preload replied")

    ArtworkURLProtocol.respond = { _ in
      started.fulfill()
      _ = release.wait(timeout: .now() + 3)
      completed.fulfill()

      return (200, png)
    }

    coordinator.preloadArtwork([artworkSource("b")])
    wait(for: [started], timeout: 3)

    var args = metadata(key: "c")
    args["artworkPath"] = local.path
    coordinator.update(NowPlayingCodec.decode(args))
    coordinator.preloadArtwork([])
    let currentReady = expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    wait(for: [currentReady], timeout: 2)

    XCTAssertEqual(artwork()?.bounds.size, image.size, "Current artwork must not wait for a speculative request")

    release.signal()
    wait(for: [completed], timeout: 3)
    let settled = expectation(description: "late preload settled")

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
    wait(for: [settled], timeout: 3)

    XCTAssertEqual(artwork()?.bounds.size, image.size)
  }

  func testClearingRejectsAnInflightPreloadAndKeepsCarPlayEmpty() {
    let session = artworkTestSession()
    let release = DispatchSemaphore(value: 0)
    defer {
      release.signal()
      session.invalidateAndCancel()
      ArtworkURLProtocol.respond = nil
    }

    coordinator = NowPlayingCoordinator(artworkSession: session)
    let png = imageData()
    let started = expectation(description: "preload started")
    let completed = expectation(description: "cancelled request completed")

    ArtworkURLProtocol.respond = { _ in
      started.fulfill()
      _ = release.wait(timeout: .now() + 3)
      completed.fulfill()

      return (200, png)
    }

    coordinator.preloadArtwork([artworkSource("b")])
    wait(for: [started], timeout: 3)
    coordinator.clear()
    release.signal()
    wait(for: [completed], timeout: 3)
    coordinator.refreshPresentation()

    XCTAssertNil(artwork())
    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
  }

  private func artworkTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtworkURLProtocol.self]

    return URLSession(configuration: configuration)
  }

  private func artworkSource(_ key: String) -> ArtworkSource {
    return ArtworkSource(
      key: key, url: "https://artwork.invalid/\(key)", token: "secret", serverPin: String(repeating: "a", count: 64)
    )
  }

  private func metadata(key: String = "album-a") -> [String: Any] {
    return [
      "trackId": "track-a",
      "title": "Track A",
      "album": "Album A",
      "artworkKey": key,
      "epoch": 1,
      "position": 12.0,
      "isPlaying": true,
    ]
  }

  private func imageData() -> Data {
    return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }.pngData()!
  }

  private func artwork() -> MPMediaItemArtwork? {
    return coordinator.buildNowPlayingInfo()[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
  }
}

/// Intercepts URLSession entirely in memory; no HTTP listener or server.
private final class ArtworkURLProtocol: URLProtocol {
  static var respond: ((URLRequest) -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let respond = Self.respond, let url = request.url else {
      return
    }

    let (status, data) = respond(request)
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
    )!

    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
