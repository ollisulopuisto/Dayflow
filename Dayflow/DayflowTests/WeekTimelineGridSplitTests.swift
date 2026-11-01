import XCTest
@testable import Dayflow

final class WeekTimelineGridSplitTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar.current
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0)
    -> Date
  {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute
    return calendar.date(from: comps)!
  }

  private func monday4AM() -> Date {
    date(2026, 10, 19, 4)  // week grids start Monday at 4 AM
  }

  private func makeActivity(start: Date, end: Date) -> TimelineActivity {
    TimelineActivity(
      id: "test",
      recordId: nil,
      batchId: nil,
      startTime: start,
      endTime: end,
      title: "Test",
      summary: "",
      detailedSummary: "",
      category: "Work",
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

  func testCrossDayActivitySplitsAt4amBoundary() {
    // Mon 10pm -> Tue 6am crosses the Tue 4am boundary
    let activity = makeActivity(
      start: date(2026, 10, 19, 22),
      end: date(2026, 10, 20, 6))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 2)
    // Piece 1: Mon 10pm -> Tue 4am in Monday's column
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 22))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 20, 4))
    // Piece 2: Tue 4am -> Tue 6am in Tuesday's column
    XCTAssertEqual(pieces[1].columnIndex, 1)
    XCTAssertEqual(pieces[1].start, date(2026, 10, 20, 4))
    XCTAssertEqual(pieces[1].end, date(2026, 10, 20, 6))
  }

  func testSingleDayActivityStaysInOneColumn() {
    // Mon 9am -> 5pm fits entirely within Monday's column
    let activity = makeActivity(
      start: date(2026, 10, 19, 9),
      end: date(2026, 10, 19, 17))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 9))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 19, 17))
  }

  func testActivityEndingBefore4amStaysInStartDayColumn() {
    // Mon 8pm -> Tue 2am ends before the Tue 4am boundary, single piece
    let activity = makeActivity(
      start: date(2026, 10, 19, 20),
      end: date(2026, 10, 20, 2))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 20))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 20, 2))
  }

  func testActivityExactlyAt4amBoundaryStartsNewColumn() {
    // Mon 4am -> Tue 4am exactly fills Monday's column
    let activity = makeActivity(
      start: date(2026, 10, 19, 4),
      end: date(2026, 10, 20, 4))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 4))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 20, 4))
  }

  func testActivityBeforeWeekWindowProducesNoPieces() {
    // Sat 6-8am is before the Mon 4am week start
    let activity = makeActivity(
      start: date(2026, 10, 17, 6),
      end: date(2026, 10, 17, 8))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertTrue(pieces.isEmpty)
  }

  func testActivityAfterWeekWindowProducesNoPieces() {
    // Following Mon 4am is exactly weekEnd (7 days later)
    let activity = makeActivity(
      start: date(2026, 10, 26, 4),
      end: date(2026, 10, 26, 6))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertTrue(pieces.isEmpty)
  }

  func testActivityStartingBeforeWeekClipsToWeekStart() {
    // Sun 10pm -> Tue 6am starts before the Mon 4am week start; clips to Mon 4am
    // then crosses the Tue 4am boundary into Tuesday's column.
    let activity = makeActivity(
      start: date(2026, 10, 18, 22),
      end: date(2026, 10, 20, 6))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 2)
    // Piece 1: clipped to Mon 4am start, ends Tue 4am
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 4))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 20, 4))
    // Piece 2: Tue 4am -> Tue 6am
    XCTAssertEqual(pieces[1].columnIndex, 1)
    XCTAssertEqual(pieces[1].start, date(2026, 10, 20, 4))
    XCTAssertEqual(pieces[1].end, date(2026, 10, 20, 6))
  }

  func testMultiDayActivitySplitsAcrossAllOverlappedColumns() {
    // Mon 8am -> Wed 6am spans Monday, Tuesday, Wednesday columns
    let activity = makeActivity(
      start: date(2026, 10, 19, 8),
      end: date(2026, 10, 21, 6))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    XCTAssertEqual(pieces.count, 3)
    XCTAssertEqual(pieces[0].columnIndex, 0)
    XCTAssertEqual(pieces[0].start, date(2026, 10, 19, 8))
    XCTAssertEqual(pieces[0].end, date(2026, 10, 20, 4))
    XCTAssertEqual(pieces[1].columnIndex, 1)
    XCTAssertEqual(pieces[1].start, date(2026, 10, 20, 4))
    XCTAssertEqual(pieces[1].end, date(2026, 10, 21, 4))
    XCTAssertEqual(pieces[2].columnIndex, 2)
    XCTAssertEqual(pieces[2].start, date(2026, 10, 21, 4))
    XCTAssertEqual(pieces[2].end, date(2026, 10, 21, 6))
  }

  func testPiecesDoNotOverlapAndCoverFullDuration() {
    let activity = makeActivity(
      start: date(2026, 10, 19, 22),
      end: date(2026, 10, 21, 10))
    let pieces = WeekTimelineGridView.splitActivityIntoDayColumns(
      activity, weekStart: monday4AM())

    var previousEnd: Date? = nil
    var totalDuration: TimeInterval = 0
    for piece in pieces {
      if let previousEnd {
        XCTAssertEqual(piece.start, previousEnd, "pieces must be contiguous")
      }
      totalDuration += piece.end.timeIntervalSince(piece.start)
      previousEnd = piece.end
    }
    XCTAssertEqual(totalDuration, activity.endTime.timeIntervalSince(activity.startTime),
                   accuracy: 1)
  }
}
