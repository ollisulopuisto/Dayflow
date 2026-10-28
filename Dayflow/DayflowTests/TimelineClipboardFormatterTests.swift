import XCTest
@testable import Dayflow

final class TimelineClipboardFormatterTests: XCTestCase {
  private func makeTestCard(
    startTimestamp: String = "10:00 AM",
    endTimestamp: String = "11:00 AM",
    category: String = "Engineering",
    subcategory: String = "Testing",
    title: String = "Writing Swift Tests",
    summary: String = "Implemented unit tests.",
    detailedSummary: String = "Added missing tests for Markdown export generation.",
    day: String = "2025-01-15"
  ) -> TimelineCard {
    TimelineCard(
      recordId: 1,
      batchId: 1,
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
      category: category,
      subcategory: subcategory,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
      day: day,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )
  }

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

  // MARK: - makeMarkdown Tests

  func testMakeMarkdownEmptyCards() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [], now: date)

    XCTAssertTrue(markdown.hasPrefix("## Dayflow timeline · "))
    XCTAssertTrue(markdown.contains("_No timeline activities were recorded for this day._"))
  }

  func testMakeMarkdownSingleCard() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let card = makeTestCard(
      startTimestamp: "10:00 AM",
      endTimestamp: "11:00 AM",
      category: "Engineering",
      title: "Writing Swift Tests",
      summary: "Implemented unit tests.",
      detailedSummary: "Added missing tests for Markdown export generation."
    )

    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [card], now: date)

    let expectedCardContent = """
    1. **10:00 AM – 11:00 AM — Writing Swift Tests**
       - _Engineering_
       - Summary: Implemented unit tests.
       - Details: Added missing tests for Markdown export generation.
    """

    XCTAssertTrue(markdown.contains(expectedCardContent))
  }

  func testMakeMarkdownMultipleCards() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let card1 = makeTestCard(title: "Task One")
    let card2 = makeTestCard(title: "Task Two")

    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [card1, card2], now: date)

    XCTAssertTrue(markdown.contains("1. **10:00 AM – 11:00 AM — Task One**"))
    XCTAssertTrue(markdown.contains("2. **10:00 AM – 11:00 AM — Task Two**"))
  }

  func testMakeMarkdownWithoutTimestampsOrCategory() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let card = makeTestCard(
      startTimestamp: "",
      endTimestamp: "   ",
      category: "  ",
      title: "Untimed Activity",
      summary: "Summary text.",
      detailedSummary: "Detailed text."
    )

    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [card], now: date)

    XCTAssertTrue(markdown.contains("1. **Untimed Activity**"))
    XCTAssertFalse(markdown.contains("- _"))
  }

  func testMakeMarkdownMultilineSummaryAndDetails() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let card = makeTestCard(
      summary: "First summary line.\nSecond summary line.",
      detailedSummary: "First detail line.\nSecond detail line."
    )

    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [card], now: date)

    let expectedSummaryBlock = """
       - Summary:
          First summary line.
          Second summary line.
    """
    let expectedDetailsBlock = """
       - Details:
          First detail line.
          Second detail line.
    """

    XCTAssertTrue(markdown.contains(expectedSummaryBlock))
    XCTAssertTrue(markdown.contains(expectedDetailsBlock))
  }

  func testMakeMarkdownOmitsDetailsWhenMatchingSummary() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let card = makeTestCard(
      summary: "Identical text.",
      detailedSummary: "Identical text.  "
    )

    let markdown = TimelineClipboardFormatter.makeMarkdown(for: date, cards: [card], now: date)

    XCTAssertTrue(markdown.contains("- Summary: Identical text."))
    XCTAssertFalse(markdown.contains("Details:"))
  }

  func testMakeMarkdownDateHeaders() {
    let calendar = Calendar.current
    let now = Date()
    let todayDate = now
    let pastDate = calendar.date(byAdding: .day, value: -5, to: now)!

    let markdownToday = TimelineClipboardFormatter.makeMarkdown(for: todayDate, cards: [], now: now)
    let markdownPast = TimelineClipboardFormatter.makeMarkdown(for: pastDate, cards: [], now: now)

    XCTAssertTrue(markdownToday.contains("Today,"))
    XCTAssertFalse(markdownPast.contains("Today,"))
  }
}
