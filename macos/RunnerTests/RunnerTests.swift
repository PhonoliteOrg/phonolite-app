import Foundation
import XCTest

import FlutterMacOS

@testable import Runner

final class RunnerTests: XCTestCase {
  func testDirectoryLauncherForwardsTheURLAndResult() {
    let directory = URL(fileURLWithPath: "/Music é/Albums", isDirectory: true)
    var received: URL?
    let launcher = DirectoryLauncher { url in
      received = url

      return false
    }

    XCTAssertFalse(launcher.openDirectory(at: directory))
    XCTAssertEqual(received, directory)
  }

  func testUnknownMethodsReplyWithoutOpeningAFolder() throws {
    let fixture = Fixture()
    let reply = try fixture.invoke("unknown", arguments: "/Music")

    XCTAssertTrue((reply as? NSObject) === FlutterMethodNotImplemented)
    XCTAssertTrue(fixture.openedURLs.isEmpty)
  }

  func testMissingWrongAndEmptyPathsReturnTheExistingError() throws {
    let invalidArguments: [Any?] = [nil, NSNull(), 42, ["path": "/Music"], ""]

    for arguments in invalidArguments {
      let fixture = Fixture()
      let reply = try fixture.invoke("openDirectory", arguments: arguments)
      let error = try XCTUnwrap(reply as? FlutterError)

      XCTAssertEqual(error.code, "invalid_path")
      XCTAssertEqual(error.message, "A folder path is required.")
      XCTAssertNil(error.details)
      XCTAssertTrue(fixture.openedURLs.isEmpty)
    }
  }

  func testAcceptedOpeningRepliesOnceWithTheExactDirectoryURL() throws {
    let fixture = Fixture()
    let path = "/Music é/Albums"
    let reply = try fixture.invoke("openDirectory", arguments: path)

    XCTAssertEqual(fixture.openedURLs, [URL(fileURLWithPath: path, isDirectory: true)])
    XCTAssertNil(reply)
  }

  func testRejectedOpeningReturnsTheExistingError() throws {
    let fixture = Fixture()
    fixture.openAccepted = false

    let reply = try fixture.invoke("openDirectory", arguments: "/Music")
    let error = try XCTUnwrap(reply as? FlutterError)

    XCTAssertEqual(fixture.openedURLs.count, 1)
    XCTAssertEqual(error.code, "open_failed")
    XCTAssertEqual(error.message, "Could not open the folder.")
    XCTAssertNil(error.details)
  }

  func testAttachmentIsIdempotent() {
    let fixture = Fixture()
    let adapter = fixture.makeAdapter()
    defer { adapter.detach() }

    adapter.attach()
    adapter.attach()

    XCTAssertTrue(adapter.isAttached)
    XCTAssertEqual(fixture.handlerChanges, 1)
  }

  func testDetachmentIsIdempotentAndUnregistersTheHandler() {
    let fixture = Fixture()
    let adapter = fixture.makeAdapter()
    adapter.attach()
    adapter.detach()
    adapter.detach()

    XCTAssertFalse(adapter.isAttached)
    XCTAssertNil(fixture.handler)
    XCTAssertEqual(fixture.handlerChanges, 2)
  }

  func testDetachmentBeforeAttachmentDoesNothing() {
    let fixture = Fixture()
    let adapter = fixture.makeAdapter()
    adapter.detach()

    XCTAssertFalse(adapter.isAttached)
    XCTAssertEqual(fixture.handlerChanges, 0)
  }

  func testAnAdapterCanAttachAgainAfterDetachment() {
    let fixture = Fixture()
    let adapter = fixture.makeAdapter()
    defer { adapter.detach() }

    adapter.attach()
    adapter.detach()
    adapter.attach()

    XCTAssertTrue(adapter.isAttached)
    XCTAssertNotNil(fixture.handler)
    XCTAssertEqual(fixture.handlerChanges, 3)
  }

  func testAnAcceptedHandlerDoesNotRetainItsAdapterOrLoseItsReply() throws {
    let fixture = Fixture()
    var adapter: DirectoriesChannelAdapter? = fixture.makeAdapter()
    weak var borrowedAdapter = adapter
    adapter?.attach()

    let handler = try XCTUnwrap(fixture.handler)
    adapter?.detach()
    adapter = nil

    XCTAssertNil(borrowedAdapter)

    var replies: [Any?] = []
    handler(FlutterMethodCall(methodName: "openDirectory", arguments: "/Music")) { replies.append($0) }

    XCTAssertEqual(replies.count, 1)
    XCTAssertNil(try XCTUnwrap(replies.first))
    XCTAssertEqual(fixture.openedURLs.count, 1)
  }
}

private final class Fixture {
  var openAccepted = true
  var openedURLs: [URL] = []
  var handler: FlutterMethodCallHandler?
  var handlerChanges = 0

  func makeAdapter() -> DirectoriesChannelAdapter {
    return DirectoriesChannelAdapter(
      openDirectory: { [self] url in
        openedURLs.append(url)

        return openAccepted
      },
      setMethodCallHandler: { [self] handler in
        self.handler = handler
        handlerChanges += 1
      }
    )
  }

  func invoke(_ method: String, arguments: Any?) throws -> Any? {
    let adapter = makeAdapter()
    adapter.attach()
    defer { adapter.detach() }

    let handler = try XCTUnwrap(handler)
    var replies: [Any?] = []
    handler(FlutterMethodCall(methodName: method, arguments: arguments)) { replies.append($0) }

    XCTAssertEqual(replies.count, 1)

    return try XCTUnwrap(replies.first)
  }
}
