import XCTest
@testable import Dayflow

final class MonthTimelineSummaryTests: XCTestCase {
  private func makeActivity(start: Date, end: Date, category: String = "Work") -> TimelineActivity {
    TimelineActivity(
      id: "test-\(start.timeIntervalSince1970)",
      recordId: nil,
      batchId: nil,
      startTime: start,
      endTime: end,
      title: "Test",
      summary: "",
      detailedSummary: "",
      category: category,
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: nil,
      screenshots: nil,
      isPendingAnalysis: false
    )
  }

  private func dayKey(for date: Date) -> String {
    date.getDayInfoFor4AMBoundary().dayString
  }

  func testCrossDayActivityIsClippedToStartDayWindow() {
    // A card that starts Sunday Oct 18 8:00 AM and ends Monday Oct 19 4:39 PM
    // spans 32 h 39 m in absolute time, but only its Sunday (4 AM→4 AM) portion
    // (8:00 AM → 4:00 AM = 20 h) belongs to Sunday.
    var startComps = DateComponents()
    startComps.year = 2026; startComps.month = 10; startComps.day = 18
    startComps.hour = 8; startComps.minute = 0
    var endComps = DateComponents()
    endComps.year = 2026; endComps.month = 10; endComps.day = 19
    endComps.hour = 16; endComps.minute = 39
    let calendar = Calendar.current
    let start = calendar.date(from: startComps)!
    let end = calendar.date(from: endComps)!

    let result = MonthTimelineSummary.summarize([makeActivity(start: start, end: end)])

    let day = dayKey(for: start)
    let seconds = result[day]?.totalSeconds ?? 0
    XCTAssertEqual(seconds, 20 * 3600, accuracy: 1, "Sunday should only get the in-window portion")
    // No single day may exceed 24 h.
    XCTAssertTrue(result.values.allSatisfy { $0.totalSeconds <= 24 * 3600 + 1 })
  }

  func testOverlappingActivitiesAreMergedNotDoubleCounted() {
    let calendar = Calendar.current
    var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 18
    c.hour = 8; c.minute = 0
    let a1Start = calendar.date(from: c)!
    c.hour = 20
    let a1End = calendar.date(from: c)!       // 8 h
    c.hour = 12; c.minute = 0
    let a2Start = calendar.date(from: c)!
    c.hour = 20; c.minute = 30
    let a2End = calendar.date(from: c)!       // 8.5 h, overlaps a1 from 12 → 8 PM

    let result = MonthTimelineSummary.summarize([
      makeActivity(start: a1Start, end: a1End),
      makeActivity(start: a2Start, end: a2End),
    ])

    let day = dayKey(for: a1Start)
    let seconds = result[day]?.totalSeconds ?? 0
    // Covered time: 8:00 AM → 8:30 PM = 12.5 h (overlap counted once)
    XCTAssertEqual(seconds, 12.5 * 3600, accuracy: 1)
    XCTAssertTrue(result.values.allSatisfy { $0.totalSeconds <= 24 * 3600 + 1 })
  }
}
