import XCTest

@testable import Dayflow

final class StudioUploadBackoffTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  func testABatchAlreadyUploadingIsNotStartedAgain() {
    var backoff = StudioUploadBackoff()
    XCTAssertTrue(backoff.tryBegin(7, now: start))
    XCTAssertFalse(backoff.tryBegin(7, now: start.addingTimeInterval(120)))
    XCTAssertTrue(backoff.tryBegin(8, now: start))
  }

  func testAFailureWaitsAMinuteBeforeTheNextAttempt() {
    var backoff = StudioUploadBackoff()
    XCTAssertTrue(backoff.tryBegin(7, now: start))
    backoff.finish(7, succeeded: false, now: start)
    XCTAssertFalse(backoff.shouldAttempt(7, now: start.addingTimeInterval(30)))
    XCTAssertTrue(backoff.shouldAttempt(7, now: start.addingTimeInterval(61)))
  }

  func testRepeatedFailuresBackOffUpToAnHour() {
    var backoff = StudioUploadBackoff()
    var now = start
    for _ in 0..<10 {
      XCTAssertTrue(backoff.tryBegin(7, now: now))
      backoff.finish(7, succeeded: false, now: now)
      now = now.addingTimeInterval(3601)
    }
    let lastFailure = now.addingTimeInterval(-3601)
    XCTAssertFalse(backoff.shouldAttempt(7, now: lastFailure.addingTimeInterval(3599)))
    XCTAssertTrue(backoff.shouldAttempt(7, now: lastFailure.addingTimeInterval(3601)))
  }

  func testSuccessClearsTheBackoff() {
    var backoff = StudioUploadBackoff()
    XCTAssertTrue(backoff.tryBegin(7, now: start))
    backoff.finish(7, succeeded: false, now: start)
    XCTAssertTrue(backoff.tryBegin(7, now: start.addingTimeInterval(61)))
    backoff.finish(7, succeeded: true, now: start.addingTimeInterval(62))
    XCTAssertTrue(backoff.shouldAttempt(7, now: start.addingTimeInterval(63)))
  }
}
