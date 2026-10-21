import XCTest

@testable import Dayflow

final class TimelineScrollStateTests: XCTestCase {
  private let footer = CGRect(x: 0, y: 500, width: 200, height: 20)

  func testFooterStaysOpaqueWhenNoLabelTouchesIt() {
    let labels = [CGRect(x: 0, y: 100, width: 40, height: 14), CGRect(x: 0, y: 300, width: 40, height: 14)]
    XCTAssertEqual(MainView.weeklyHoursFadeLevel(labelFrames: labels, hoursFrame: footer, fadeDistance: 12), 1)
  }

  func testFooterFadesWithTheOverlapInFivePercentSteps() {
    // 6pt of a 12pt fade distance overlaps, so the footer is half visible.
    let labels = [CGRect(x: 0, y: 494, width: 40, height: 12)]
    XCTAssertEqual(MainView.weeklyHoursFadeLevel(labelFrames: labels, hoursFrame: footer, fadeDistance: 12), 0.5)
    // A one-point scroll that does not cross a 5% step gives the same level, so no state write.
    let nudged = [CGRect(x: 0, y: 494.2, width: 40, height: 12)]
    XCTAssertEqual(MainView.weeklyHoursFadeLevel(labelFrames: nudged, hoursFrame: footer, fadeDistance: 12), 0.5)
  }

  func testFooterIsOpaqueBeforeItHasBeenMeasured() {
    let labels = [CGRect(x: 0, y: 494, width: 40, height: 12)]
    XCTAssertEqual(MainView.weeklyHoursFadeLevel(labelFrames: labels, hoursFrame: .zero, fadeDistance: 12), 1)
  }
}

final class TimelineReloadGateTests: XCTestCase {
  func testSilentRefreshWithTheSameCardsCommitsNothing() {
    XCTAssertFalse(TimelineReloadGate.shouldCommit(animate: false, old: ["a|1", "b|2"], new: ["a|1", "b|2"]))
  }

  func testChangedCardsAreCommitted() {
    XCTAssertTrue(TimelineReloadGate.shouldCommit(animate: false, old: ["a|1"], new: ["a|1", "b|2"]))
  }

  func testAnimatedLoadsAlwaysCommit() {
    XCTAssertTrue(TimelineReloadGate.shouldCommit(animate: true, old: ["a|1"], new: ["a|1"]))
  }

  func testEntranceDelayIsCapped() {
    XCTAssertEqual(TimelineReloadGate.entranceDelay(index: 3), 0.09, accuracy: 0.0001)
    XCTAssertEqual(TimelineReloadGate.entranceDelay(index: 100), 0.3, accuracy: 0.0001)
  }
}

final class TimelineActivateReloadTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testActivatingRightAfterALoadDoesNotLoadAgain() {
    XCTAssertFalse(TimelineReloadGate.shouldReloadOnActivate(lastLoadStart: now.addingTimeInterval(-0.5), now: now))
  }

  func testActivatingLaterReloads() {
    XCTAssertTrue(TimelineReloadGate.shouldReloadOnActivate(lastLoadStart: now.addingTimeInterval(-30), now: now))
    XCTAssertTrue(TimelineReloadGate.shouldReloadOnActivate(lastLoadStart: nil, now: now))
  }
}
