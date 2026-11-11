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
  func testSearchKeepsAllTotalsAndSplitsMatchedCoverage() {
    let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    var first = makeActivity(start: day, end: day.addingTimeInterval(3600))
    first = first.withTitle("Foxy Bear")
    var second = makeActivity(start: day.addingTimeInterval(3600), end: day.addingTimeInterval(7200))
    second = second.withTitle("Unrelated")
    let all = MonthTimelineSummary.summarize([first, second])
    let searched = MonthTimelineSummary.summarize([first, second], searchTerms: ["foxy"])
    let key = dayKey(for: day)
    XCTAssertEqual(searched[key]?.totalSeconds, all[key]?.totalSeconds)
    XCTAssertEqual(searched[key]?.secondsByCategory, all[key]?.secondsByCategory)
    XCTAssertEqual(searched[key]?.matchingSecondsByCategory[categoryFilterKey("Work")], 3600)
    XCTAssertEqual(searched[key]?.firstMatchingIDByCategory[categoryFilterKey("Work")], first.id)
    let noMatches = MonthTimelineSummary.summarize([first, second], searchTerms: ["missing"])
    XCTAssertEqual(noMatches[key]?.secondsByCategory, all[key]?.secondsByCategory)
    XCTAssertTrue(noMatches[key]?.firstMatchingIDByCategory.isEmpty == true)
    XCTAssertTrue(all[key]?.matchingSecondsByCategory.isEmpty == true)
  }

  func testFirstMatchIsChronologicalRegardlessOfInputOrderAndCategory() {
    let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    var early = makeActivity(start: day, end: day.addingTimeInterval(60))
    early = early.withTitle("Foxy early")
    var late = makeActivity(start: day.addingTimeInterval(120), end: day.addingTimeInterval(180))
    late = late.withTitle("Foxy late")
    var personal = makeActivity(start: day.addingTimeInterval(240), end: day.addingTimeInterval(300), category: "Personal")
    personal = personal.withTitle("Foxy personal")
    let result = MonthTimelineSummary.summarize([late, personal, early], searchTerms: ["foxy"])
    XCTAssertEqual(result[dayKey(for: day)]?.firstMatchingIDByCategory[categoryFilterKey("Work")], early.id)
    XCTAssertEqual(result[dayKey(for: day)]?.firstMatchingIDByCategory[categoryFilterKey("Personal")], personal.id)
    let muted = MonthTimelineSummary.summarize([early], mutedCategoryKeys: [categoryFilterKey("Work")], searchTerms: ["foxy"])
    XCTAssertTrue(muted.isEmpty)
  }

  func testCross4AMMatchRemainsNavigableOnBothDays() {
    let midnight = Calendar.current.startOfDay(for: Date())
    let start = Calendar.current.date(bySettingHour: 3, minute: 30, second: 0, of: midnight)!
    let end = Calendar.current.date(bySettingHour: 4, minute: 30, second: 0, of: midnight)!
    var crossDay = makeActivity(start: start, end: end)
    crossDay = crossDay.withTitle("Foxy overnight")
    let result = MonthTimelineSummary.summarize([crossDay], searchTerms: ["foxy"])
    XCTAssertEqual(result.count, 2)
    for summary in result.values {
      XCTAssertEqual(summary.firstMatchingIDByCategory[categoryFilterKey("Work")], crossDay.id)
      XCTAssertEqual(summary.matchingSecondsByCategory[categoryFilterKey("Work")], 1800)
    }
  }

  func testOverlappingSameCategoryMatchIsBrightWithoutChangingCoverage() {
    let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    let outer = makeActivity(start: day, end: day.addingTimeInterval(7200))
    let match = makeActivity(start: day.addingTimeInterval(1800), end: day.addingTimeInterval(3600))
      .withTitle("Foxy")
    let result = MonthTimelineSummary.summarize([outer, match], searchTerms: ["foxy"])
    let summary = result[dayKey(for: day)]
    XCTAssertEqual(summary?.totalSeconds, 7200)
    XCTAssertEqual(summary?.matchingSecondsByCategory[categoryFilterKey("Work")], 1800)
  }

}
