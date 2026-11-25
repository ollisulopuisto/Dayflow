import XCTest
import GRDB
@testable import Dayflow

/// Executes the same migration entry point used at startup against isolated legacy databases.
final class RecordedTimeZoneMigrationTests: XCTestCase {
  private func legacyDatabase() throws -> DatabaseQueue {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE analysis_batches(id INTEGER PRIMARY KEY, status TEXT);
        CREATE TABLE timeline_cards(
          id INTEGER PRIMARY KEY, start TEXT, start_ts INTEGER, day TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0, summary TEXT
        );
        INSERT INTO analysis_batches VALUES (1, 'completed');
        INSERT INTO timeline_cards VALUES
          (1, '3:34 PM', 1790663640, '2026-09-29', 0, 'keep live'),
          (2, '9:00 AM', 1794859200, '2026-11-17', 0, 'keep Auckland'),
          (3, 'not a clock', 1790663640, '2026-09-29', 0, 'keep invalid'),
          (4, '3:34 PM', NULL, '2026-09-29', 0, 'keep no timestamp'),
          (5, '3:34 PM', 1790663640, '2026-09-29', 1, 'keep deleted');
        """)
    }
    return queue
  }

  func testLegacyBackfillPreservesRowsAndSkipsUnparseableDeletedAndMissingTimestamp() throws {
    let queue = try legacyDatabase()
    let before = try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM timeline_cards ORDER BY id") }
    try queue.write { try StorageManager.migrateRecordedTimeZones($0) }
    try queue.read { db in
      XCTAssertTrue(try db.columns(in: "analysis_batches").contains { $0.name == "time_zone" })
      XCTAssertNil(try String.fetchOne(db, sql: "SELECT time_zone FROM analysis_batches WHERE id = 1"))
      let offsets = try Row.fetchAll(db, sql: "SELECT utc_offset FROM timeline_cards ORDER BY id")
      XCTAssertEqual(offsets[0]["utc_offset"] as Int?, 9 * 3600)
      XCTAssertEqual(offsets[1]["utc_offset"] as Int?, 13 * 3600)
      for index in 2...4 { XCTAssertNil(offsets[index]["utc_offset"] as Int?) }
      let after = try Row.fetchAll(db, sql: "SELECT id, start, start_ts, day, is_deleted, summary FROM timeline_cards ORDER BY id")
      XCTAssertEqual(after, before)
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM analysis_batches"), "completed")
    }
  }

  func testRepeatedStartupDoesNotOverwriteExistingOffsetsOrBatchZone() throws {
    let queue = try legacyDatabase()
    try queue.write { db in
      try StorageManager.migrateRecordedTimeZones(db)
      try db.execute(sql: "UPDATE timeline_cards SET utc_offset = 12345 WHERE id = 1")
      try db.execute(sql: "UPDATE analysis_batches SET time_zone = 'Asia/Tokyo'")
      try StorageManager.migrateRecordedTimeZones(db)
    }
    try queue.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT utc_offset FROM timeline_cards WHERE id = 1"), 12345)
      XCTAssertEqual(try String.fetchOne(db, sql: "SELECT time_zone FROM analysis_batches"), "Asia/Tokyo")
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timeline_cards"), 5)
    }
  }

  func testEnclosingStartupTransactionRollsBackSchemaAndBackfillOnFailure() throws {
    enum Stop: Error { case intentional }
    let queue = try legacyDatabase()
    XCTAssertThrowsError(try queue.write { db in
      try StorageManager.migrateRecordedTimeZones(db)
      throw Stop.intentional
    })
    try queue.read { db in
      XCTAssertFalse(try db.columns(in: "timeline_cards").contains { $0.name == "utc_offset" })
      XCTAssertFalse(try db.columns(in: "analysis_batches").contains { $0.name == "time_zone" })
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timeline_cards"), 5)
    }
  }
}
