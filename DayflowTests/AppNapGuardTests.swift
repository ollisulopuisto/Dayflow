import XCTest

@testable import Dayflow

final class AppNapGuardTests: XCTestCase {

  private final class FakePower {
    var begins: [(ProcessInfo.ActivityOptions, String)] = []
    var ends = 0
    var shouldGrantActivity = true

    func makeGuard() -> AppNapGuard {
      AppNapGuard(
        beginActivity: { options, reason in
          self.begins.append((options, reason))
          return self.shouldGrantActivity ? NSObject() : nil
        },
        endActivity: { _ in self.ends += 1 })
    }
  }

  func testHoldBeginsUserInitiatedActivityAllowingIdleSystemSleep() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    guard_.hold(reason: "recording")

    XCTAssertEqual(power.begins.count, 1)
    XCTAssertEqual(power.begins.first?.0, .userInitiatedAllowingIdleSystemSleep)
    XCTAssertEqual(power.begins.first?.1, "recording")
    XCTAssertTrue(guard_.isHolding)
  }

  func testHoldingTwiceKeepsOneAssertion() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    guard_.hold(reason: "recording")
    guard_.hold(reason: "recording")

    XCTAssertEqual(power.begins.count, 1)
  }

  func testReleaseEndsOnceAndIsIdempotent() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    guard_.release()
    XCTAssertEqual(power.ends, 0, "releasing without a hold is a no-op")

    guard_.hold(reason: "recording")
    guard_.release()
    guard_.release()

    XCTAssertEqual(power.ends, 1)
    XCTAssertFalse(guard_.isHolding)
  }

  func testAHoldAfterReleaseBeginsAgain() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    guard_.hold(reason: "recording")
    guard_.release()
    guard_.hold(reason: "recording")

    XCTAssertEqual(power.begins.count, 2)
    XCTAssertEqual(power.ends, 1)
    XCTAssertTrue(guard_.isHolding)
  }

  func testRecorderStatesHoldOnlyWhileStartingOrCapturing() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    RecorderState.idle.updateAppNapGuard(guard_)
    XCTAssertEqual(power.begins.count, 0)
    XCTAssertEqual(power.ends, 0)

    RecorderState.starting.updateAppNapGuard(guard_)
    XCTAssertEqual(power.begins.count, 1)
    XCTAssertTrue(guard_.isHolding)

    // Transitioning to active capture must preserve the same assertion.
    RecorderState.capturing.updateAppNapGuard(guard_)
    XCTAssertEqual(power.begins.count, 1)
    XCTAssertEqual(power.ends, 0)

    RecorderState.paused.updateAppNapGuard(guard_)
    XCTAssertEqual(power.ends, 1)
    XCTAssertFalse(guard_.isHolding)

    // A resumed capture obtains a fresh assertion; stopping releases it.
    RecorderState.starting.updateAppNapGuard(guard_)
    XCTAssertEqual(power.begins.count, 2)
    RecorderState.capturing.updateAppNapGuard(guard_)
    RecorderState.idle.updateAppNapGuard(guard_)
    XCTAssertEqual(power.ends, 2)
    XCTAssertFalse(guard_.isHolding)
  }

  func testDeinitializingGuardReleasesHeldActivity() {
    let power = FakePower()
    var guard_: AppNapGuard? = power.makeGuard()
    guard_?.hold(reason: "recording")

    guard_ = nil

    XCTAssertEqual(power.ends, 1)
  }

  func testFailedActivityAcquisitionDoesNotClaimToBeHolding() {
    let power = FakePower()
    power.shouldGrantActivity = false
    let guard_ = power.makeGuard()

    guard_.hold(reason: "recording")

    XCTAssertFalse(guard_.isHolding)
    guard_.release()
    XCTAssertEqual(power.ends, 0)
  }
}
