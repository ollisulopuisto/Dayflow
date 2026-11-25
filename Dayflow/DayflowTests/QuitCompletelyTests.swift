import AppKit
import SwiftUI
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
  func testOrdinaryQuitTerminatesInsteadOfHiding() {
    AppDelegate.allowTermination = false
    XCTAssertEqual(AppDelegate().applicationShouldTerminate(NSApplication.shared), .terminateNow)
  }

  func testHideDoesNotEnableTermination() {
    AppDelegate.allowTermination = false
    var hidden = false
    AppShortcutRegistry.hideApplication { hidden = true }
    XCTAssertTrue(hidden)
    XCTAssertFalse(AppDelegate.allowTermination)
    XCTAssertEqual(AppShortcutRegistry.quit.key, KeyEquivalent("q"))
    XCTAssertEqual(AppShortcutRegistry.quit.modifiers, .command)
    XCTAssertEqual(AppShortcutRegistry.hide.key, KeyEquivalent("h"))
    XCTAssertEqual(AppShortcutRegistry.hide.modifiers, .command)
  }

}
