import XCTest

@testable import Dayflow

final class WeeklyDefaultWeekTests: XCTestCase {
  private let thisWeek = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_800_000_000))

  func testPicksTheNewestWeekWithEnoughData() {
    let twoBack = thisWeek.shifted(byWeeks: -2)
    let result = WeeklyDefaultWeek.search(
      from: thisWeek, searchLimit: 52, requirementMinutes: 900
    ) { range in range == twoBack ? 1000 : 0 }
    XCTAssertEqual(result, twoBack)
  }

  func testFallsBackToTheNewestWeekWithAnyData() {
    let oneBack = thisWeek.shifted(byWeeks: -1)
    let result = WeeklyDefaultWeek.search(
      from: thisWeek, searchLimit: 52, requirementMinutes: 900
    ) { range in range == oneBack ? 30 : 0 }
    XCTAssertEqual(result, oneBack)
  }

  func testStaysOnTheStartWeekWithoutData() {
    let result = WeeklyDefaultWeek.search(
      from: thisWeek, searchLimit: 52, requirementMinutes: 900
    ) { _ in 0 }
    XCTAssertEqual(result, thisWeek)
  }
}
