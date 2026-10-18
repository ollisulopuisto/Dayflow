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

    let blocks = TimelineActivityLoader.resolveWeekMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 14))
    XCTAssertEqual(blocks[0].activity.title, "Main task")
    XCTAssertEqual(blocks[1].activity.category, "Idle")
  }

  func testWeekMacroblocksKeepSeparateAcrossAGap() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 5, title: "Task", category: "Engineering"),
      activity(id: "b", startMinute: 7, endMinute: 10, title: "Task", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveWeekMacroblocks(from: segments)

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
