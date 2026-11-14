import XCTest

@testable import Dayflow

/// The retry and redaction rules of `BrowserPrivacy.redactionLabel`, run against a scripted
/// check instead of a live browser. Nothing here touches the network or AppleScript.
final class BrowserPrivacyRetryTests: XCTestCase {

  /// Hands out scripted results in order and counts the attempts.
  private final class ScriptedCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<BrowserPrivacy.State, BrowserPrivacy.CheckFailure>]
    private var calls = 0

    init(_ results: [Result<BrowserPrivacy.State, BrowserPrivacy.CheckFailure>]) {
      self.results = results
    }

    var attempts: Int {
      lock.lock()
      defer { lock.unlock() }
      return calls
    }

    func next() -> Result<BrowserPrivacy.State, BrowserPrivacy.CheckFailure> {
      lock.lock()
      defer { lock.unlock() }
      calls += 1
      // Past the script, repeat the last answer so an unexpected extra call is visible
      // in `attempts` rather than a crash.
      return results[min(calls, results.count) - 1]
    }
  }

  private let visible = BrowserPrivacy.State(isIncognito: false, url: "https://example.org/")

  private func label(
    _ check: ScriptedCheck,
    hidesIncognito: Bool = true,
    excludedDomains: [String] = []
  ) async -> String? {
    await BrowserPrivacy.redactionLabel(
      hidesIncognito: hidesIncognito,
      excludedDomains: excludedDomains,
      bundleID: "com.google.Chrome"
    ) {
      check.next()
    }
  }

  func testACleanFirstCheckIsNotRetriedAndAllowsCapture() async {
    let check = ScriptedCheck([.success(visible)])
    let result = await label(check)
    XCTAssertNil(result)
    XCTAssertEqual(check.attempts, 1)
  }

  func testATransientFailureIsRetriedOnceAndRecovers() async {
    let check = ScriptedCheck([.failure(.timedOut), .success(visible)])
    let result = await label(check)
    XCTAssertNil(result, "the retry succeeded, so the window may be captured")
    XCTAssertEqual(check.attempts, 2)
  }

  func testRecoveryStillRedactsAPrivateWindow() async {
    let privateState = BrowserPrivacy.State(isIncognito: true, url: nil)
    let check = ScriptedCheck([.failure(.browserNotRunning), .success(privateState)])
    let result = await label(check)
    XCTAssertEqual(result, BrowserPrivacy.label(for: .privateWindow))
    XCTAssertEqual(check.attempts, 2)
  }

  func testRecoveryStillRedactsAnExcludedSite() async {
    let site = BrowserPrivacy.State(isIncognito: false, url: "https://bank.example.com/login")
    let check = ScriptedCheck([.failure(.noWindow), .success(site)])
    let result = await label(check, excludedDomains: ["example.com"])
    XCTAssertEqual(result, BrowserPrivacy.label(for: .excludedSite))
    XCTAssertEqual(check.attempts, 2)
  }

  func testRepeatedFailureRedactsWithTheLastCauseAndStopsAfterTwoAttempts() async {
    let check = ScriptedCheck([.failure(.timedOut), .failure(.unexpectedOutput)])
    let result = await label(check)
    XCTAssertEqual(result, BrowserPrivacy.unavailableLabel(cause: .unexpectedOutput))
    XCTAssertEqual(check.attempts, 2, "one retry, never a third attempt")
  }

  func testCausesThatCannotChangeAreNotRetriedAndAreRedacted() async {
    let causes: [BrowserPrivacy.CheckFailure] = [
      .notAuthorized, .scriptUnavailable, .privateStateUnverifiable,
    ]
    for cause in causes {
      let check = ScriptedCheck([.failure(cause), .success(visible)])
      let result = await label(check)
      XCTAssertEqual(result, BrowserPrivacy.unavailableLabel(cause: cause))
      XCTAssertEqual(check.attempts, 1, "\(cause) must not be retried")
    }
  }

  func testRetryRuleCoversEveryFailureCase() {
    let retryable: [BrowserPrivacy.CheckFailure] = [
      .timedOut, .browserNotRunning, .noWindow, .unexpectedOutput, .windowTitleUnavailable,
      .appleScriptError(-1),
    ]
    for cause in retryable { XCTAssertTrue(BrowserPrivacy.isRetryable(cause), "\(cause)") }
    let fixed: [BrowserPrivacy.CheckFailure] = [
      .notAuthorized, .scriptUnavailable, .privateStateUnverifiable,
    ]
    for cause in fixed { XCTAssertFalse(BrowserPrivacy.isRetryable(cause), "\(cause)") }
  }
}
