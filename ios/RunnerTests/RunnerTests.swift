import Flutter
import MediaPlayer
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  private var coordinator: NowPlayingCoordinator!

  override func setUp() {
    super.setUp()
    coordinator = NowPlayingCoordinator()
  }

  override func tearDown() {
    coordinator.clear(carPlaySceneDelegate: nil)
    coordinator = nil
    super.tearDown()
  }

  private func metadata(key: String = "album-a") -> [String: Any] {
    ["trackId": "track-a", "title": "Track A", "album": "Album A",
     "artworkKey": key, "epoch": 1, "position": 12.0, "isPlaying": true]
  }

  private func imageData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }.pngData()!
  }

  private func artwork() -> MPMediaItemArtwork? {
    coordinator.buildNowPlayingInfo()[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
  }

  func testArtworkSurvivesPositionUpdatesWithoutBeingRecreated() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    let first = artwork()
    XCTAssertNotNil(first)
    args["position"] = 15.0
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    XCTAssertTrue(first === artwork())
    let requested = CGSize(width: 10, height: 10)
    XCTAssertEqual(first?.image(at: requested)?.size, requested)
  }

  func testChangingAlbumsClearsThePreviousCover() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    XCTAssertNotNil(artwork())
    coordinator.update(args: metadata(key: "album-b"), carPlaySceneDelegate: nil)
    XCTAssertNil(artwork())
  }

  func testConsecutiveTracksInAnAlbumKeepTheArtworkObject() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    let first = artwork()
    args["trackId"] = "track-b"
    args["title"] = "Track B"
    args["epoch"] = 2
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    XCTAssertTrue(first === artwork())
    XCTAssertEqual(coordinator.buildNowPlayingInfo()[MPMediaItemPropertyTitle] as? String, "Track B")
  }

  func testReturningToAnAlbumReusesDecodedArtworkWithoutReadingTheFileAgain() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try imageData().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    var args = metadata()
    args["artworkPath"] = url.path
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)
    let first = artwork()

    coordinator.update(args: metadata(key: "album-b"), carPlaySceneDelegate: nil)
    XCTAssertNil(artwork())
    try FileManager.default.removeItem(at: url)
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    XCTAssertTrue(first === artwork())

    coordinator.clear(carPlaySceneDelegate: nil)
    coordinator.update(args: args, carPlaySceneDelegate: nil)
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
    coordinator.update(args: args, carPlaySceneDelegate: nil)
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
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    args["artworkKey"] = "album-b"
    args["trackId"] = "track-b"
    args["artworkPath"] = second.path
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
    waitForExpectations(timeout: 3)
    XCTAssertEqual(artwork()?.bounds.size, image.size)
  }

  func testCorruptBytesDoNotDiscardAValidCover() {
    var args = metadata()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: imageData())
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    let first = artwork()
    args["artworkBytes"] = FlutterStandardTypedData(bytes: Data([0, 1, 2]))
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    XCTAssertTrue(first === artwork())
  }

  func testSeekEpochAllowsPositionToMoveBackward() {
    coordinator.update(args: metadata(), carPlaySceneDelegate: nil)
    var args = metadata()
    args["epoch"] = 2
    args["position"] = 2.0
    coordinator.update(args: args, carPlaySceneDelegate: nil)
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
    coordinator.update(args: args, carPlaySceneDelegate: nil)
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
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    expectation(for: NSPredicate { [weak self] _, _ in
      guard let self else { return false }
      // Position updates are what trigger retry in normal playback.
      self.coordinator.update(args: args, carPlaySceneDelegate: nil)
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
      self.coordinator.update(args: args, carPlaySceneDelegate: nil)
      self.expectation(for: NSPredicate { [weak self] _, _ in self?.artwork() != nil }, evaluatedWith: nil)
      self.waitForExpectations(timeout: 3)
    }
    load()
    let first = artwork()
    coordinator.update(args: metadata(key: "album-b"), carPlaySceneDelegate: nil)
    coordinator.update(args: args, carPlaySceneDelegate: nil)
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
    coordinator.update(args: args, carPlaySceneDelegate: nil)
    coordinator.clear(carPlaySceneDelegate: nil)
    coordinator.refreshForCarPlay(force: true, carPlaySceneDelegate: nil)
    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    // Drain the asynchronous file completion after the clear operation.
    let settled = expectation(description: "artwork completion settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
    waitForExpectations(timeout: 3)
    XCTAssertNil(artwork())
    XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
  }
}

/// Intercepts URLSession entirely in memory; no HTTP listener or server.
private final class ArtworkURLProtocol: URLProtocol {
  static var respond: ((URLRequest) -> (Int, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let respond = Self.respond, let url = request.url else { return }
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
