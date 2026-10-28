import XCTest
import GRDB
@testable import Dayflow

/// Pins the SQL semantics behind the "N hours of activities tracked this week"
/// footer: only the in-range overlap of each non-deleted, non-System card counts.
/// The footer goes stale when nothing refreshes it (fixed by wiring it to the
/// week grid's load); this test guards the query itself.
final class StorageManagerWeeklyTrackedMinutesTests: XCTestCase {
  private let store = StorageManager.shared

  // Distant-past window (2001-09-09) so no real usage rows interfere.
  private let rangeStartTs = 1_000_000_000
  private var rangeEndTs: Int { rangeStartTs + 8 * 3600 }
  private var batchId: Int64 = 0

  override func setUpWithError() throws {
    try store.db.write { db in
      try db.execute(
        sql: "INSERT INTO analysis_batches(batch_start_ts, batch_end_ts, status) VALUES (?, ?, 'test')",
        arguments: [rangeStartTs, rangeEndTs])
      batchId = db.lastInsertedRowID
    }
  }

  override func tearDownWithError() throws {
    try store.db.write { db in
      try db.execute(
        sql: "DELETE FROM timeline_cards WHERE title LIKE 'weekly-total-test-%'")
      try db.execute(sql: "DELETE FROM analysis_batches WHERE id = ?", arguments: [batchId])
    }
  }

  private func insertCard(
    _ title: String, startTs: Int, endTs: Int,
    category: String = "Engineering", deleted: Int = 0
  ) {
    try? store.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO timeline_cards(
            batch_id, start, end, start_ts, end_ts, day, title,
            summary, category, subcategory, detailed_summary, metadata, is_deleted
          ) VALUES (?, '', '', ?, ?, '2001-09-09', ?, '', ?, '', '', '{}', ?)
          """,
        arguments: [batchId, startTs, endTs, title, category, deleted])
    }
  }

  private func trackedMinutes() -> Double {
    store.fetchTotalMinutesTracked(
      from: Date(timeIntervalSince1970: TimeInterval(rangeStartTs)),
      to: Date(timeIntervalSince1970: TimeInterval(rangeEndTs)))
  }

  func testEmptyRangeSumsToZero() {
    XCTAssertEqual(trackedMinutes(), 0, accuracy: 0.01)
  }

  func testCountsFullAndPartialOverlapsOnly() {
    // 30 min fully inside
    insertCard("weekly-total-test-inside", startTs: rangeStartTs + 600, endTs: rangeStartTs + 2400)
    // Straddles the start: 20 of 40 min inside
    insertCard("weekly-total-test-straddle-start", startTs: rangeStartTs - 1200, endTs: rangeStartTs + 1200)
    // Straddles the end: 15 of 45 min inside
    insertCard("weekly-total-test-straddle-end", startTs: rangeEndTs - 900, endTs: rangeEndTs + 1800)
    // Fully outside: not counted
    insertCard("weekly-total-test-outside", startTs: rangeEndTs + 3600, endTs: rangeEndTs + 7200)

    XCTAssertEqual(trackedMinutes(), 30 + 20 + 15, accuracy: 0.01)
  }

  func testDeletedAndSystemCardsAreExcluded() {
    insertCard("weekly-total-test-counted", startTs: rangeStartTs + 60, endTs: rangeStartTs + 660)
    insertCard("weekly-total-test-deleted", startTs: rangeStartTs + 60, endTs: rangeStartTs + 3660, deleted: 1)
    insertCard("weekly-total-test-system", startTs: rangeStartTs + 60, endTs: rangeStartTs + 3660, category: "System")

    XCTAssertEqual(trackedMinutes(), 10, accuracy: 0.01)
  }
}
