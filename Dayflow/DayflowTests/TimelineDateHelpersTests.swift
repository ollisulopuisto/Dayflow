import XCTest

@testable import Dayflow

final class TimelineDateHelpersTests: XCTestCase {
  func testNormalizedTimelineDateIsNoonOfSameDay() {
    let calendar = Calendar.current
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 3, minute: 17))!
    let normalized = normalizedTimelineDate(start)
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: normalized)
    XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 10, 21])
    XCTAssertEqual([parts.hour, parts.minute, parts.second], [12, 0, 0])
  }

  func testNormalizedTimelineDateMatchesSettingHourAcrossTwoYears() {
    let calendar = Calendar.current
    let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
    for offset in 0..<730 {
      let date = calendar.date(byAdding: .day, value: offset, to: base)!
      XCTAssertEqual(
        normalizedTimelineDate(date),
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date), "offset \(offset)")
    }
  }

  func testTimelineDisplayDateBefore4AMBelongsToPreviousDay() {
    let calendar = Calendar.current
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 2))!
    let shown = timelineDisplayDate(from: now, now: now)
    XCTAssertEqual(calendar.component(.day, from: shown), 21)
    XCTAssertTrue(timelineIsToday(shown, now: now))
  }
}
