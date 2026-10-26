import UIKit
import XCTest

@testable import Runner

final class LaunchSnapshotCoverTests: XCTestCase {
  func testBackgroundSnapshotCoversContentAndUsesTheLaunchLogo() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = UIViewController()

    controller.view.backgroundColor = .red
    window.rootViewController = controller

    let presentation = LaunchSnapshotCover()

    presentation.show(in: window)

    let cover = try XCTUnwrap(window.subviews.last)
    let logo = try XCTUnwrap(cover.subviews.compactMap { $0 as? UIImageView }.first)

    XCTAssertFalse(cover === controller.view)
    XCTAssertEqual(cover.frame, window.bounds)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    XCTAssertTrue(try XCTUnwrap(cover.backgroundColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    XCTAssertEqual(red, 5 / 255, accuracy: 0.000001)
    XCTAssertEqual(green, red)
    XCTAssertEqual(blue, red)
    XCTAssertEqual(alpha, 1)
    XCTAssertNotNil(logo.image)
    XCTAssertEqual(logo.bounds.size, CGSize(width: 220, height: 220))
    XCTAssertEqual(logo.center, CGPoint(x: window.bounds.midX, y: window.bounds.midY))

    let subviewCount = window.subviews.count

    presentation.show(in: window)

    XCTAssertEqual(window.subviews.count, subviewCount, "Repeated background events must not stack covers")

    presentation.remove()

    XCTAssertNil(cover.superview)
    XCTAssertTrue(window.rootViewController === controller, "Resuming must retain the existing navigation/UI")
    XCTAssertEqual(controller.view.backgroundColor, .red)

    presentation.remove()
    presentation.show(in: window)

    XCTAssertTrue(window.subviews.last !== controller.view, "The next background cycle must show a cover again")

    presentation.remove()
  }

  func testCoverResizesWithTheWindow() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let presentation = LaunchSnapshotCover()

    presentation.show(in: window)
    window.bounds.size = CGSize(width: 844, height: 390)
    window.layoutIfNeeded()

    let cover = try XCTUnwrap(window.subviews.last)
    let logo = try XCTUnwrap(cover.subviews.compactMap { $0 as? UIImageView }.first)

    XCTAssertEqual(cover.frame, window.bounds)
    XCTAssertEqual(logo.center, CGPoint(x: window.bounds.midX, y: window.bounds.midY))

    presentation.remove()
  }

  func testMissingWindowDoesNotPreventALaterCover() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let presentation = LaunchSnapshotCover()

    presentation.show(in: nil)
    presentation.show(in: window)

    XCTAssertFalse(window.subviews.isEmpty)

    presentation.remove()

    XCTAssertTrue(window.subviews.isEmpty)
  }
}
