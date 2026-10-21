import XCTest

@testable import Dayflow

final class DailyGoalPromptDecisionTests: XCTestCase {
  private func decide(hasPlan: Bool = false, activeDays: Int = 5, skipStreak: Int = 0)
    -> DailyGoalPromptDecision
  {
    DailyGoalPromptDecision.evaluate(
      hasPlan: hasPlan, activeDays: activeDays, skipStreak: skipStreak,
      requiredActiveDays: 3, maxSkips: 5)
  }

  func testADayWithAPlanIsHandled() {
    XCTAssertEqual(decide(hasPlan: true), .alreadyPlanned)
  }

  func testNewUsersAreNotPromptedYet() {
    XCTAssertEqual(decide(activeDays: 2), .notYet)
  }

  func testFiveSkipsInARowStopThePrompt() {
    XCTAssertEqual(decide(skipStreak: 5), .notYet)
  }

  func testOtherwiseThePromptIsShown() {
    XCTAssertEqual(decide(), .prompt)
  }
}
