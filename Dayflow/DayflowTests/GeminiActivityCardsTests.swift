import XCTest

@testable import Dayflow

final class GeminiActivityCardsTests: XCTestCase {
  private let provider = GeminiDirectProvider(apiKey: "test-key")

  func testValidateTimeCoverageSkipsZeroOrNegativeDurationCards() {
    let existingCards = [
      makeCard(start: "9:00 AM", end: "9:15 AM", title: "Valid input card"),
      makeCard(start: "9:15 AM", end: "9:15 AM", title: "Zero duration input card"),
    ]

    let generatedCards = [
      makeCard(start: "9:00 AM", end: "9:00 AM", title: "Zero duration output card"),
      makeCard(start: "9:00 AM", end: "9:15 AM", title: "Valid output card"),
    ]

    let result = provider.validateTimeCoverage(
      existingCards: existingCards,
      newCards: generatedCards
    )

    XCTAssertTrue(result.isValid)
    XCTAssertNil(result.error)
  }

  func testValidateTimelineRejectsZeroOrNegativeDurationCards() {
    // Zero duration card as final card
    let zeroDurationFinalCards = [
      makeCard(start: "9:00 AM", end: "9:30 AM", title: "First card"),
      makeCard(start: "9:30 AM", end: "9:30 AM", title: "Zero duration final card"),
    ]

    let zeroResult = provider.validateTimeline(zeroDurationFinalCards)
    XCTAssertFalse(zeroResult.isValid)
    XCTAssertEqual(zeroResult.error, "Card 2 'Zero duration final card' has zero or negative duration")

    // Negative duration card
    let negativeDurationCards = [
      makeCard(start: "9:30 AM", end: "9:15 AM", title: "Negative duration card")
    ]

    let negativeResult = provider.validateTimeline(negativeDurationCards)
    XCTAssertFalse(negativeResult.isValid)
    XCTAssertEqual(negativeResult.error, "Card 1 'Negative duration card' has zero or negative duration")
  }

  func testValidateTimelineAcceptsValidCards() {
    let validCards = [
      makeCard(start: "9:00 AM", end: "9:20 AM", title: "First card"),
      makeCard(start: "9:20 AM", end: "9:25 AM", title: "Short final card"),
    ]

    let result = provider.validateTimeline(validCards)
    XCTAssertTrue(result.isValid)
    XCTAssertNil(result.error)
  }

  private func makeCard(
    start: String,
    end: String,
    category: String = "Focus",
    title: String
  ) -> ActivityCardData {
    ActivityCardData(
      startTime: start,
      endTime: end,
      category: category,
      subcategory: "",
      title: title,
      summary: "Summary",
      detailedSummary: "Details",
      distractions: nil,
      appSites: nil
    )
  }
}
