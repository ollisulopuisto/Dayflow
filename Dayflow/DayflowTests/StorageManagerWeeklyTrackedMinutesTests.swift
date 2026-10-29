import XCTest
import GRDB
@testable import Dayflow

/// Pins the semantics behind the "N hours of activities tracked this week"
/// footer: the in-range overlap of each non-deleted, non-System card counts,
/// plus capture time still waiting for analysis (the grid shows it as
/// "Waiting for analysis" blocks, so the footer must match).
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
      try db.execute(
        sql: "DELETE FROM analysis_batches WHERE batch_end_ts >= ? AND batch_start_ts <= ?",
        arguments: [rangeStartTs, rangeEndTs])
      try db.execute(sql: "DELETE FROM screenshots WHERE file_path LIKE 'weekly-total-test-%'")
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

  func testPendingAnalysisBatchTimeIsCounted() {
    // 10-min analysed card + a pending batch straddling the range end (60 of 90 min inside).
    insertCard("weekly-total-test-card", startTs: rangeStartTs + 60, endTs: rangeStartTs + 660)
    try? store.db.write { db in
      try db.execute(
        sql: "INSERT INTO analysis_batches(batch_start_ts, batch_end_ts, status) VALUES (?, ?, 'pending')",
        arguments: [rangeEndTs - 3600, rangeEndTs + 1800])
    }

    XCTAssertEqual(trackedMinutes(), 10 + 60, accuracy: 0.01)
  }

  func testUnbatchedCapturesCountedAndNonPendingBatchesAreNot() {
    // A completed batch contributes no pending time (its cards count instead),
    // and the setUp batch (status 'test') must not count either.
    try? store.db.write { db in
      try db.execute(
        sql: "INSERT INTO analysis_batches(batch_start_ts, batch_end_ts, status) VALUES (?, ?, 'completed')",
        arguments: [rangeStartTs + 7200, rangeStartTs + 9000])
      // Three unbatched captures 2 min apart: one 4-min pending span.
      for ts in [rangeStartTs + 3600, rangeStartTs + 3720, rangeStartTs + 3840] {
        try db.execute(
          sql: "INSERT INTO screenshots(captured_at, file_path) VALUES (?, ?)",
          arguments: [ts, "weekly-total-test-\(ts).png"])
      }
    }

    XCTAssertEqual(trackedMinutes(), 4, accuracy: 0.01)
  }
}
