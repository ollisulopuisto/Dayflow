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

@MainActor
final class CLIVersionTelemetryPublicationTests: XCTestCase {
  func testCachedHeartbeatsRegisterOnceWithoutPersonEvents() {
    var state = CLIVersionTelemetryPublication()
    var registrations: [[String: String]] = []
    var people: [[String: String]] = []
    for _ in 0..<24 {
      state.publish(["codex_cli_version": "1.2"], freshProbe: false, optedIn: true,
        register: { registrations.append($0) }, setPerson: { people.append($0) })
    }
    XCTAssertEqual(registrations.count, 1)
    XCTAssertTrue(people.isEmpty)
    // A new process restores its cached super properties independently.
    var relaunched = CLIVersionTelemetryPublication()
    relaunched.publish(["codex_cli_version": "1.2"], freshProbe: false, optedIn: true,
      register: { registrations.append($0) }, setPerson: { people.append($0) })
    XCTAssertEqual(registrations.count, 2)
    XCTAssertTrue(people.isEmpty)
  }

  func testFreshProbeAndChangedValuesUpdatePersonOnce() {
    var state = CLIVersionTelemetryPublication()
    var registrations: [[String: String]] = []
    var people: [[String: String]] = []
    for version in ["1.2", "1.2", "1.3", "1.3"] {
      state.publish(["codex_cli_version": version], freshProbe: true, optedIn: true,
        register: { registrations.append($0) }, setPerson: { people.append($0) })
    }
    XCTAssertEqual(registrations.count, 2)
    XCTAssertEqual(people, [["codex_cli_version": "1.2"], ["codex_cli_version": "1.3"]])
  }

  func testOptOutAndEmptyPropertiesMakeNoCallsThenOptInRestores() {
    var state = CLIVersionTelemetryPublication()
    var calls = 0
    let sink: ([String: String]) -> Void = { _ in calls += 1 }
    state.publish([:], freshProbe: true, optedIn: true, register: sink, setPerson: sink)
    state.publish(["v": "1"], freshProbe: true, optedIn: false, register: sink, setPerson: sink)
    XCTAssertEqual(calls, 0)
    state.publish(["v": "1"], freshProbe: true, optedIn: true, register: sink, setPerson: sink)
    XCTAssertEqual(calls, 2)
    state.publish(["v": "1"], freshProbe: true, optedIn: false, register: sink, setPerson: sink)
    XCTAssertEqual(calls, 2)
    state.publish(["v": "1"], freshProbe: false, optedIn: true, register: sink, setPerson: sink)
    XCTAssertEqual(calls, 3)
  }
}
