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

    AppDelegate.quitCompletely(confirm: { true }) { terminateCalls += 1 }

    XCTAssertTrue(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReason, "app_menu_quit")
    XCTAssertEqual(terminateCalls, 1)
  }
  func testStatusBarQuitConfirmsBeforeFullTermination() {
    var confirmations = 0
    var terminateCalls = 0
    StatusBarController.requestQuit(confirm: { confirmations += 1; return true }) { terminateCalls += 1 }
    XCTAssertEqual(confirmations, 1)
    XCTAssertEqual(terminateCalls, 1)
    XCTAssertTrue(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReason, "menu_bar_quit")
    XCTAssertEqual(AppDelegate.terminationReply(confirm: { XCTFail("must not prompt twice"); return false }), .terminateNow)
  }

  func testStatusBarCancelDoesNotQuitOrPermitTermination() {
    var terminateCalls = 0
    StatusBarController.requestQuit(confirm: { false }) { terminateCalls += 1 }
    XCTAssertEqual(terminateCalls, 0)
    XCTAssertFalse(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReason, "unknown")
  }

  func testOrdinaryQuitTerminatesInsteadOfHiding() {
    AppDelegate.allowTermination = false
    XCTAssertEqual(AppDelegate.terminationReply(confirm: { true }), .terminateNow)
  }

  func testCancelledQuitDoesNotTerminateOrPermitTermination() {
    AppDelegate.allowTermination = false
    var terminateCalls = 0
    AppDelegate.quitCompletely(confirm: { false }) { terminateCalls += 1 }
    XCTAssertEqual(terminateCalls, 0)
    XCTAssertFalse(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReply(confirm: { false }), .terminateCancel)
    XCTAssertFalse(AppDelegate.allowTermination)
    XCTAssertEqual(AppDelegate.terminationReason, "unknown")
  }

  func testExplicitRestartDoesNotAskForOrdinaryQuitConfirmation() {
    AppDelegate.permitTermination(reason: "permission_restart")
    XCTAssertEqual(AppDelegate.terminationReply(confirm: { XCTFail("restart must not prompt"); return false }), .terminateNow)
    XCTAssertEqual(AppDelegate.terminationReason, "permission_restart")
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
