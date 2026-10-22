import XCTest

@testable import Dayflow

final class TimelineActivityLoaderTests: XCTestCase {
  func testCreateDisplaySegmentsGroupsConsecutiveFailures() {
    let activities = [
      activity(
        id: "failure-3", startMinute: 31, endMinute: 46, title: "Processing failed", batchId: 3),
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 15, endMinute: 30, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.createDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].activity.id, "failure-1")
    XCTAssertEqual(segments[0].failureCount, 3)
    XCTAssertEqual(segments[0].batchIds, [1, 2, 3])
    XCTAssertEqual(segments[0].start, date(minute: 0))
    XCTAssertEqual(segments[0].end, date(minute: 46))
  }

  func testCreateDisplaySegmentsDoesNotGroupAcrossAnotherActivity() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(id: "idle", startMinute: 15, endMinute: 30, title: "Idle"),
      activity(
        id: "failure-2", startMinute: 30, endMinute: 45, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.createDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 3)
    XCTAssertEqual(segments.map(\.failureCount), [1, 0, 1])
  }

  func testCreateDisplaySegmentsDoesNotGroupFailuresSeparatedByMoreThanOneMinute() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 17, endMinute: 32, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.createDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments.map(\.failureCount), [1, 1])
  }

  func testWeekMacroblocksJoinAlternatingCategoriesIntoTenMinuteBlocks() {
    let segments = TimelineActivityLoader.createDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 4, title: "Coding", category: "Engineering"),
      activity(id: "b", startMinute: 4, endMinute: 5, title: "Chat", category: "Communication"),
      activity(id: "c", startMinute: 5, endMinute: 9, title: "Coding more", category: "Engineering"),
      activity(id: "d", startMinute: 9, endMinute: 10, title: "Personal", category: "Personal"),
      activity(id: "e", startMinute: 10, endMinute: 12, title: "Coding last", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveWeekMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 10))
    XCTAssertEqual(blocks[0].activity.category, "Engineering")
    XCTAssertEqual(blocks[1].activity.category, "Engineering")
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
