import XCTest

@testable import Dayflow

final class AppNapGuardTests: XCTestCase {

  private final class FakePower {
    var begins: [(ProcessInfo.ActivityOptions, String)] = []
    var ends = 0

    func makeGuard() -> AppNapGuard {
      AppNapGuard(
        beginActivity: { options, reason in
          self.begins.append((options, reason))
          return NSObject()
        },
        endActivity: { _ in self.ends += 1 })
    }
  }

  func testHoldBeginsABackgroundActivityWithTheReason() {
    let power = FakePower()
    let guard_ = power.makeGuard()

    guard_.hold(reason: "recording")

    XCTAssertEqual(power.begins.count, 1)
    XCTAssertEqual(power.begins.first?.0, .background)
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
}
