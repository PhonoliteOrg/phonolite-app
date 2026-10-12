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
