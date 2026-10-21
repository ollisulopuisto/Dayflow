import XCTest

@testable import Dayflow

final class LaunchIntroTests: XCTestCase {
  func testIntroPlaysOnlyBeforeOnboardingIsDone() {
    XCTAssertTrue(LaunchIntro.shouldPlay(didOnboard: false))
    XCTAssertFalse(LaunchIntro.shouldPlay(didOnboard: true))
  }
}
