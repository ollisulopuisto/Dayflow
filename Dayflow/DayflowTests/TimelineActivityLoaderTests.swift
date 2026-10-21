import XCTest

@testable import Dayflow

final class TimelineActivityLoaderTests: XCTestCase {
  func testResolveDisplaySegmentsGroupsConsecutiveFailures() {
    let activities = [
      activity(
        id: "failure-3", startMinute: 31, endMinute: 46, title: "Processing failed", batchId: 3),
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 15, endMinute: 30, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].activity.id, "failure-1")
    XCTAssertEqual(segments[0].failureCount, 3)
    XCTAssertEqual(segments[0].batchIds, [1, 2, 3])
    XCTAssertEqual(segments[0].start, date(minute: 0))
    XCTAssertEqual(segments[0].end, date(minute: 46))
  }

  func testResolveDisplaySegmentsDoesNotGroupAcrossAnotherActivity() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(id: "idle", startMinute: 15, endMinute: 30, title: "Idle"),
      activity(
        id: "failure-2", startMinute: 30, endMinute: 45, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 3)
    XCTAssertEqual(segments.map(\.failureCount), [1, 0, 1])
  }

  func testResolveDisplaySegmentsDoesNotGroupFailuresSeparatedByMoreThanOneMinute() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 17, endMinute: 32, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments.map(\.failureCount), [1, 1])
  }

  func testWeekMacroblocksMergeConsecutiveSameCategory() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 5, title: "Short task", category: "Engineering"),
      activity(id: "b", startMinute: 5, endMinute: 14, title: "Main task", category: "Engineering"),
      activity(id: "c", startMinute: 14, endMinute: 20, title: "Idle", category: "Idle"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 14))
    XCTAssertEqual(blocks[0].activity.title, "Main task")
    XCTAssertEqual(blocks[1].activity.category, "Idle")
  }

  func testWeekMacroblocksJoinAlternatingCategoriesIntoTenMinuteBlocks() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 4, title: "Coding", category: "Engineering"),
      activity(id: "b", startMinute: 4, endMinute: 5, title: "Chat", category: "Communication"),
      activity(id: "c", startMinute: 5, endMinute: 9, title: "Coding more", category: "Engineering"),
      activity(id: "d", startMinute: 9, endMinute: 10, title: "Personal", category: "Personal"),
      activity(id: "e", startMinute: 10, endMinute: 12, title: "Coding last", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 10))
    XCTAssertEqual(blocks[0].activity.category, "Engineering")
    XCTAssertEqual(blocks[1].activity.category, "Engineering")
  }

  func testWeekMacroblocksKeepSeparateAcrossAGap() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 5, title: "Task", category: "Engineering"),
      activity(id: "b", startMinute: 7, endMinute: 10, title: "Task", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
  }

  private func activity(
    id: String,
    startMinute: Int,
    endMinute: Int,
    title: String,
    batchId: Int64? = nil,
    category: String? = nil
  ) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: nil,
      batchId: batchId,
      startTime: date(minute: startMinute),
      endTime: date(minute: endMinute),
      title: title,
      summary: "",
      detailedSummary: "",
      category: category ?? (title == "Idle" ? "Idle" : "System"),
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: false
    )
  }

  private func date(minute: Int) -> Date {
    Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60))
  }
}

final class SidebarShortcutTests: XCTestCase {
  func testCommandNumbersSelectTheMainSectionsInSidebarOrder() {
    XCTAssertEqual(SidebarIcon.forCommandNumber(1), .timeline)
    XCTAssertEqual(SidebarIcon.forCommandNumber(2), .daily)
    XCTAssertEqual(SidebarIcon.forCommandNumber(3), .weekly)
    XCTAssertEqual(SidebarIcon.forCommandNumber(4), .chat)
    XCTAssertEqual(SidebarIcon.forCommandNumber(5), .flow)
    XCTAssertEqual(SidebarIcon.forCommandNumber(6), .agents)
  }

  func testCommandNumbersOutsideTheMainSectionsSelectNothing() {
    XCTAssertNil(SidebarIcon.forCommandNumber(0))
    XCTAssertNil(SidebarIcon.forCommandNumber(7))
    XCTAssertNil(SidebarIcon.forCommandNumber(9))
  }
}

final class SidebarFlowVisibilityTests: XCTestCase {
  func testHidingFlowRemovesOnlyFlowFromTheSidebar() {
    let visible = SidebarIcon.visibleIcons(hideFlow: true)
    XCTAssertFalse(visible.contains(.flow))
    XCTAssertEqual(visible.count, SidebarIcon.allCases.count - 1)
    XCTAssertTrue(visible.contains(.timeline))
    XCTAssertTrue(visible.contains(.settings))
  }

  func testShowingFlowKeepsTheFullSidebar() {
    XCTAssertEqual(SidebarIcon.visibleIcons(hideFlow: false), SidebarIcon.allCases)
  }
}

final class TimelineZoomAndHintTests: XCTestCase {
  func testZoomInMovesFromWeekToDayAndStopsAtDay() {
    XCTAssertEqual(TimelineMode.week.zoomed(by: 1), .day)
    XCTAssertEqual(TimelineMode.day.zoomed(by: 1), .day)
  }

  func testZoomOutMovesFromDayToWeekAndStopsAtWeek() {
    XCTAssertEqual(TimelineMode.day.zoomed(by: -1), .week)
    XCTAssertEqual(TimelineMode.week.zoomed(by: -1), .week)
  }

  func testSidebarShortcutLabelsAreVisibleText() {
    XCTAssertEqual(SidebarIcon.timeline.shortcutLabel, "⌘1")
    XCTAssertEqual(SidebarIcon.agents.shortcutLabel, "⌘6")
    XCTAssertEqual(SidebarIcon.settings.shortcutLabel, "⌘,")
  }

  func testSidebarHintsShowCommandNumbers() {
    XCTAssertEqual(SidebarIcon.timeline.shortcutHint, "Timeline (⌘1)")
    XCTAssertEqual(SidebarIcon.agents.shortcutHint, "Agents (⌘6)")
    XCTAssertEqual(SidebarIcon.settings.shortcutHint, "Settings (⌘,)")
  }
}
