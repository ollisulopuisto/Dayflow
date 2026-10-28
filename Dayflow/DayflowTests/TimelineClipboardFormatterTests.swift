import XCTest
@testable import Dayflow

final class TimelineClipboardFormatterTests: XCTestCase {
  func testFormattedRangeWithValidStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "11:00 AM"),
      "10:00 AM – 11:00 AM"
    )
  }

  func testFormattedRangeWithEmptyStart() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "", end: "11:00 AM"),
      "11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "   ", end: "11:00 AM"),
      "11:00 AM"
    )
  }

  func testFormattedRangeWithEmptyEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: ""),
      "10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "   "),
      "10:00 AM"
    )
  }

  func testFormattedRangeWithEmptyStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "", end: ""),
      ""
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "   ", end: "  \n "),
      ""
    )
  }

  func testFormattedRangeWithWhitespacePadding() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "  10:00 AM  ", end: "  11:00 AM  "),
      "10:00 AM – 11:00 AM"
    )
  }

  // MARK: - Card Sorting Tests

  private func makeCard(
    day: String = "2025-01-15",
    startTimestamp: String = "9:00 AM",
    endTimestamp: String = "10:00 AM",
    title: String = "Activity"
  ) -> TimelineCard {
    TimelineCard(
      recordId: nil,
      batchId: nil,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      category: "Work",
      subcategory: "Coding",
      title: title,
      summary: "Summary",
      detailedSummary: "Details",
      day: day,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )
  }

  func testCardSortByDay() {
    let cardDay1 = makeCard(day: "2025-01-15", startTimestamp: "5:00 PM", title: "Z Activity")
    let cardDay2 = makeCard(day: "2025-01-16", startTimestamp: "8:00 AM", title: "A Activity")

    XCTAssertTrue(TimelineClipboardFormatter.cardSort(lhs: cardDay1, rhs: cardDay2))
    XCTAssertFalse(TimelineClipboardFormatter.cardSort(lhs: cardDay2, rhs: cardDay1))

    let sorted = [cardDay2, cardDay1].sorted(by: TimelineClipboardFormatter.cardSort)
    XCTAssertEqual(sorted.map(\.day), ["2025-01-15", "2025-01-16"])
  }

  func testCardSortByStartTime() {
    let morningCard = makeCard(day: "2025-01-15", startTimestamp: "9:00 AM", title: "Z Activity")
    let lateMorningCard = makeCard(day: "2025-01-15", startTimestamp: "11:30 AM", title: "M Activity")
    let afternoonCard = makeCard(day: "2025-01-15", startTimestamp: "1:15 PM", title: "A Activity")

    XCTAssertTrue(TimelineClipboardFormatter.cardSort(lhs: morningCard, rhs: lateMorningCard))
    XCTAssertTrue(TimelineClipboardFormatter.cardSort(lhs: lateMorningCard, rhs: afternoonCard))
    XCTAssertFalse(TimelineClipboardFormatter.cardSort(lhs: afternoonCard, rhs: morningCard))

    let unsorted = [afternoonCard, morningCard, lateMorningCard]
    let sorted = unsorted.sorted(by: TimelineClipboardFormatter.cardSort)
    XCTAssertEqual(sorted.map(\.startTimestamp), ["9:00 AM", "11:30 AM", "1:15 PM"])
  }

  func testCardSortByTitleWhenDayAndStartTimeAreEqual() {
    let cardAlpha = makeCard(day: "2025-01-15", startTimestamp: "9:00 AM", title: "Alpha Task")
    let cardBeta = makeCard(day: "2025-01-15", startTimestamp: "9:00 AM", title: "Beta Task")

    XCTAssertTrue(TimelineClipboardFormatter.cardSort(lhs: cardAlpha, rhs: cardBeta))
    XCTAssertFalse(TimelineClipboardFormatter.cardSort(lhs: cardBeta, rhs: cardAlpha))

    let sorted = [cardBeta, cardAlpha].sorted(by: TimelineClipboardFormatter.cardSort)
    XCTAssertEqual(sorted.map(\.title), ["Alpha Task", "Beta Task"])
  }

  func testCardSortWithUnparseableStartTimes() {
    let cardUnparseableA = makeCard(
      day: "2025-01-15",
      startTimestamp: "Invalid Time",
      title: "Alpha Task"
    )
    let cardUnparseableB = makeCard(
      day: "2025-01-15",
      startTimestamp: "Invalid Time",
      title: "Beta Task"
    )

    XCTAssertTrue(TimelineClipboardFormatter.cardSort(lhs: cardUnparseableA, rhs: cardUnparseableB))
    XCTAssertFalse(TimelineClipboardFormatter.cardSort(lhs: cardUnparseableB, rhs: cardUnparseableA))

    let sorted = [cardUnparseableB, cardUnparseableA].sorted(by: TimelineClipboardFormatter.cardSort)
    XCTAssertEqual(sorted.map(\.title), ["Alpha Task", "Beta Task"])
  }
}
