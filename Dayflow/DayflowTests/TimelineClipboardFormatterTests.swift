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

  // MARK: - Daily Clipboard Formatting Tests

  func testMakeClipboardTextForDailyEmptyCardsOnToday() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))
    let targetDate = now

    let result = TimelineClipboardFormatter.makeClipboardText(for: targetDate, cards: [], now: now)

    XCTAssertTrue(result.contains("Dayflow timeline · Today,"))
    XCTAssertTrue(result.contains("No timeline activities were recorded for this day."))
  }

  func testMakeClipboardTextForDailyEmptyCardsOnPastDate() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))
    let pastDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 10, hour: 10, minute: 0)))

    let result = TimelineClipboardFormatter.makeClipboardText(for: pastDate, cards: [], now: now)

    XCTAssertTrue(result.contains("Dayflow timeline · "))
    XCTAssertFalse(result.contains("Today,"))
    XCTAssertTrue(result.contains("No timeline activities were recorded for this day."))
  }

  func testMakeClipboardTextForDailyWithCards() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))
    let targetDate = now

    let card1 = TimelineCard(
      recordId: 1,
      batchId: 100,
      startTimestamp: "9:00 AM",
      endTimestamp: "10:00 AM",
      category: "Work",
      subcategory: "Coding",
      title: "  Developing Feature A  ",
      summary: " Implemented new feature ",
      detailedSummary: " Added unit tests and refactored code ",
      day: "2025-02-15",
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    let card2 = TimelineCard(
      recordId: 2,
      batchId: 101,
      startTimestamp: "10:00 AM",
      endTimestamp: "10:30 AM",
      category: "Meeting",
      subcategory: "Sync",
      title: "Team Standup",
      summary: "Line 1\nLine 2",
      detailedSummary: "Line 1\nLine 2", // identical to summary, shouldn't duplicate details section
      day: "2025-02-15",
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    let result = TimelineClipboardFormatter.makeClipboardText(for: targetDate, cards: [card1, card2], now: now)

    XCTAssertTrue(result.contains("Dayflow timeline · Today,"))

    // Check entry 1
    XCTAssertTrue(result.contains("1. 9:00 AM – 10:00 AM — Developing Feature A"))
    XCTAssertTrue(result.contains("   Work"))
    XCTAssertTrue(result.contains("   Summary: Implemented new feature"))
    XCTAssertTrue(result.contains("   Details: Added unit tests and refactored code"))

    // Check entry 2
    XCTAssertTrue(result.contains("2. 10:00 AM – 10:30 AM — Team Standup"))
    XCTAssertTrue(result.contains("   Meeting"))
    XCTAssertTrue(result.contains("   Summary:\n      Line 1\n      Line 2"))
    // Detailed summary is same as summary, so "Details:" should not appear for card 2
    XCTAssertFalse(result.contains("Details:\n      Line 1"))
  }

  // MARK: - Weekly Clipboard Formatting Tests

  func testMakeClipboardTextForWeeklyEmptyCards() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))
    let weekRange = TimelineWeekRange.containing(now)

    let result = TimelineClipboardFormatter.makeClipboardText(for: weekRange, cards: [], now: now)

    XCTAssertTrue(result.contains("Dayflow timeline · "))
    XCTAssertTrue(result.contains("No timeline activities were recorded for this week."))
  }

  func testMakeClipboardTextForWeeklyWithCards() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))
    let weekRange = TimelineWeekRange.containing(now)

    guard let firstDayString = weekRange.days.first?.dayString,
          let secondDayString = weekRange.days.dropFirst().first?.dayString else {
      XCTFail("Week range should have days")
      return
    }

    let card1 = TimelineCard(
      recordId: 1,
      batchId: 100,
      startTimestamp: "2:00 PM",
      endTimestamp: "3:00 PM",
      category: "Work",
      subcategory: "",
      title: "Task B (later in day)",
      summary: "Summary B",
      detailedSummary: "Details B",
      day: firstDayString,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    let card2 = TimelineCard(
      recordId: 2,
      batchId: 101,
      startTimestamp: "9:00 AM",
      endTimestamp: "10:00 AM",
      category: "Work",
      subcategory: "",
      title: "Task A (earlier in day)",
      summary: "Summary A",
      detailedSummary: "Details A",
      day: firstDayString,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    let card3 = TimelineCard(
      recordId: 3,
      batchId: 102,
      startTimestamp: "11:00 AM",
      endTimestamp: "12:00 PM",
      category: "Personal",
      subcategory: "",
      title: "Task C",
      summary: "Summary C",
      detailedSummary: "",
      day: secondDayString,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    // Pass cards in unsorted order (card1 before card2)
    let result = TimelineClipboardFormatter.makeClipboardText(for: weekRange, cards: [card1, card2, card3], now: now)

    XCTAssertTrue(result.contains("Dayflow timeline · "))

    // Verify sorting within firstDayString: card2 (9:00 AM) should come before card1 (2:00 PM)
    guard let rangeTaskA = result.range(of: "1. 9:00 AM – 10:00 AM — Task A (earlier in day)"),
          let rangeTaskB = result.range(of: "2. 2:00 PM – 3:00 PM — Task B (later in day)") else {
      XCTFail("Both tasks should be present in clipboard output")
      return
    }

    XCTAssertTrue(rangeTaskA.lowerBound < rangeTaskB.lowerBound)
    XCTAssertTrue(result.contains("1. 11:00 AM – 12:00 PM — Task C"))
  }

  // MARK: - Markdown Formatting Tests

  func testMakeMarkdownForEmptyCards() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))

    let result = TimelineClipboardFormatter.makeMarkdown(for: now, cards: [], now: now)

    XCTAssertTrue(result.hasPrefix("## Dayflow timeline · Today,"))
    XCTAssertTrue(result.contains("_No timeline activities were recorded for this day._"))
  }

  func testMakeMarkdownWithCards() throws {
    let calendar = Calendar.current
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 10, minute: 0)))

    let card = TimelineCard(
      recordId: 1,
      batchId: 100,
      startTimestamp: "9:00 AM",
      endTimestamp: "10:00 AM",
      category: "Development",
      subcategory: "",
      title: "Coding Session",
      summary: "Single line summary",
      detailedSummary: "Multi line\ndetails summary",
      day: "2025-02-15",
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )

    let result = TimelineClipboardFormatter.makeMarkdown(for: now, cards: [card], now: now)

    XCTAssertTrue(result.hasPrefix("## Dayflow timeline · Today,"))
    XCTAssertTrue(result.contains("1. **9:00 AM – 10:00 AM — Coding Session**"))
    XCTAssertTrue(result.contains("   - _Development_"))
    XCTAssertTrue(result.contains("   - Summary: Single line summary"))
    XCTAssertTrue(result.contains("   - Details:\n      Multi line\n      details summary"))
  }

  func testFormattedRangeWithNewlineAndTabWhitespace() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\t10:00 AM\n", end: "\r\n11:00 AM\t"),
      "10:00 AM – 11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\n\t  ", end: "11:00 AM"),
      "11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "\r\n\t"),
      "10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\r\n\t ", end: "\n\n\t"),
      ""
    )
  }

  func testFormattedRangeWithIdenticalStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "10:00 AM"),
      "10:00 AM – 10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: " 10:00 AM \n", end: "\t10:00 AM "),
      "10:00 AM – 10:00 AM"
    )
  }
}
