import XCTest

@testable import Dayflow

@MainActor
final class QuitCompletelyTests: XCTestCase {
  override func tearDown() {
    AppDelegate.allowTermination = false
    AppDelegate.terminationReason = "unknown"
    super.tearDown()
  }

  func testQuitCompletelyPermitsTerminationWithItsOwnReason() {
    AppDelegate.allowTermination = false
    var terminateCalls = 0

    AppDelegate.quitCompletely { terminateCalls += 1 }

    XCTAssertTrue(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReason, "app_menu_quit")
    XCTAssertEqual(terminateCalls, 1)
  }
}
