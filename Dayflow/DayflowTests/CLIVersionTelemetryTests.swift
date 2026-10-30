import XCTest

@testable import Dayflow

final class CLIVersionTelemetryTests: XCTestCase {
  func testNeverRefreshedIsStale() {
    XCTAssertTrue(CLIVersionTelemetry.isStale(lastRefresh: nil, now: Date()))
  }

  func testRefreshWithinTwentyFourHoursIsNotStale() {
    let now = Date()
    XCTAssertFalse(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(-3600), now: now))
    XCTAssertFalse(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(-24 * 3600 + 1), now: now))
  }

  func testRefreshAtOrBeyondTwentyFourHoursIsStale() {
    let now = Date()
    XCTAssertTrue(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(-24 * 3600), now: now))
    XCTAssertTrue(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(-7 * 24 * 3600), now: now))
  }

  func testClockRollbackDoesNotSuppressVersionProbesUntilTheFutureDate() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertTrue(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(3600), now: now))
    XCTAssertTrue(
      CLIVersionTelemetry.isStale(lastRefresh: now.addingTimeInterval(7 * 24 * 3600), now: now))
    XCTAssertFalse(CLIVersionTelemetry.isStale(lastRefresh: now, now: now))
  }

  func testNumericVersionExtractsLeadingVersion() {
    XCTAssertEqual(CLIVersionTelemetry.numericVersion("2.1.4 (Claude Code)"), "2.1.4")
    XCTAssertEqual(CLIVersionTelemetry.numericVersion("v1.2.3"), "1.2.3")
    XCTAssertEqual(CLIVersionTelemetry.numericVersion("no version here"), "unknown")
  }
}
