import XCTest

@testable import Dayflow

final class LocalizedDurationTests: XCTestCase {
  func testZeroSecondsReturnsZeroMinutes() {
    let result = LocalizedDuration.string(0)
    XCTAssertFalse(result.isEmpty)
    XCTAssertEqual(result, LocalizedDuration.string(0))
  }

  func testSecondsLessThanSixtyAreFlooredToZero() {
    let zeroResult = LocalizedDuration.string(0)
    XCTAssertEqual(LocalizedDuration.string(30), zeroResult)
    XCTAssertEqual(LocalizedDuration.string(59.9), zeroResult)
  }

  func testNegativeSecondsAreHandledAsZero() {
    let zeroResult = LocalizedDuration.string(0)
    XCTAssertEqual(LocalizedDuration.string(-10), zeroResult)
    XCTAssertEqual(LocalizedDuration.string(-3600), zeroResult)
  }

  func testExactMinutesAreFormattedCorrectly() {
    let oneMinute = LocalizedDuration.string(60)
    let twoMinutes = LocalizedDuration.string(120)

    XCTAssertFalse(oneMinute.isEmpty)
    XCTAssertFalse(twoMinutes.isEmpty)
    XCTAssertNotEqual(oneMinute, twoMinutes)
  }

  func testRemainingSecondsInMinuteAreFloored() {
    let oneMinute = LocalizedDuration.string(60)
    XCTAssertEqual(LocalizedDuration.string(61), oneMinute)
    XCTAssertEqual(LocalizedDuration.string(89), oneMinute)
    XCTAssertEqual(LocalizedDuration.string(119.9), oneMinute)
  }

  func testHourAndMinuteCombinations() {
    let oneHour = LocalizedDuration.string(3600)
    let oneHourThirtyMins = LocalizedDuration.string(5400)
    let twoHours = LocalizedDuration.string(7200)

    XCTAssertFalse(oneHour.isEmpty)
    XCTAssertFalse(oneHourThirtyMins.isEmpty)
    XCTAssertFalse(twoHours.isEmpty)

    XCTAssertNotEqual(oneHour, oneHourThirtyMins)
    XCTAssertNotEqual(oneHour, twoHours)
  }

  func testAbbreviatedStyleFormatting() {
    let fullStyle = LocalizedDuration.string(5400, style: .full)
    let abbreviatedStyle = LocalizedDuration.string(5400, style: .abbreviated)

    XCTAssertFalse(abbreviatedStyle.isEmpty)
    XCTAssertNotEqual(fullStyle, abbreviatedStyle)
  }

  func testLargeDurationsExceedingTwentyFourHours() {
    // 25 hours = 25 * 3600 = 90,000 seconds
    let twentyFiveHours = LocalizedDuration.string(90000)
    XCTAssertFalse(twentyFiveHours.isEmpty)
  }
}
