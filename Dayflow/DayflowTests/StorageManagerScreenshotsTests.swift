import XCTest
import GRDB
@testable import Dayflow

final class StorageManagerScreenshotsTests: XCTestCase {

  func testSaveBatchWithScreenshotsReturnsNilWhenEmpty() {
    let store = StorageManager.shared
    let batchId = store.saveBatchWithScreenshots(startTs: 1_000_000, endTs: 1_000_100, screenshotIds: [])
    XCTAssertNil(batchId)
  }

  func testSaveBatchWithScreenshotsSingleChunk() {
    let store = StorageManager.shared
    guard let shotId1 = store.saveScreenshot(segmentPath: "/tmp/seg1.mp4", frameIndex: 0, capturedAt: Date(timeIntervalSince1970: 1_000_000), idleSecondsAtCapture: nil),
          let shotId2 = store.saveScreenshot(segmentPath: "/tmp/seg1.mp4", frameIndex: 1, capturedAt: Date(timeIntervalSince1970: 1_000_005), idleSecondsAtCapture: nil)
    else {
      XCTFail("Failed to insert initial screenshots")
      return
    }

    let batchId = store.saveBatchWithScreenshots(
      startTs: 1_000_000,
      endTs: 1_000_100,
      screenshotIds: [shotId1, shotId2]
    )

    XCTAssertNotNil(batchId)
    if let batchId = batchId {
      let screenshots = store.screenshotsForBatch(batchId)
      XCTAssertEqual(screenshots.count, 2)
      XCTAssertEqual(screenshots.map(\.id), [shotId1, shotId2])
    }
  }

  func testSaveBatchWithScreenshotsMultiChunk() {
    let store = StorageManager.shared
    let initialTs = 2_000_000
    var shotIds: [Int64] = []

    // Insert 900 screenshots to test chunking logic (> 400 items per batch)
    for i in 0..<900 {
      if let shotId = store.saveScreenshot(
        segmentPath: "/tmp/multichunk.mp4",
        frameIndex: i,
        capturedAt: Date(timeIntervalSince1970: TimeInterval(initialTs + i)),
        idleSecondsAtCapture: nil
      ) {
        shotIds.append(shotId)
      }
    }

    XCTAssertEqual(shotIds.count, 900)

    let batchId = store.saveBatchWithScreenshots(
      startTs: initialTs,
      endTs: initialTs + 900,
      screenshotIds: shotIds
    )

    XCTAssertNotNil(batchId)
    if let batchId = batchId {
      let screenshots = store.screenshotsForBatch(batchId)
      XCTAssertEqual(screenshots.count, 900)
      XCTAssertEqual(screenshots.map(\.id), shotIds)
    }
  }

  func testScreenshotsForBatchesEmptyInput() {
    XCTAssertTrue(StorageManager.shared.screenshotsForBatches([]).isEmpty)
  }

  func testScreenshotsForBatchesGroupsAndSortsByBatch() {
    let store = StorageManager.shared
    let baseTs = 4_000_000
    var ids: [Int64] = []
    for i in 0..<4 {
      guard
        let id = store.saveScreenshot(
          segmentPath: "/tmp/dayflow-grouped-\(i).mp4",
          frameIndex: 0,
          capturedAt: Date(timeIntervalSince1970: TimeInterval(baseTs + i)),
          idleSecondsAtCapture: nil
        )
      else {
        XCTFail("Failed to insert screenshot \(i)")
        return
      }
      ids.append(id)
    }

    // Two batches with interleaved capture times.
    guard
      let batchA = store.saveBatchWithScreenshots(
        startTs: baseTs, endTs: baseTs + 3, screenshotIds: [ids[0], ids[2]]),
      let batchB = store.saveBatchWithScreenshots(
        startTs: baseTs + 1, endTs: baseTs + 4, screenshotIds: [ids[1], ids[3]])
    else {
      XCTFail("Failed to create batches")
      return
    }

    let grouped = store.screenshotsForBatches([batchA, batchB])
    XCTAssertEqual(grouped[batchA]?.map(\.id), [ids[0], ids[2]])
    XCTAssertEqual(grouped[batchB]?.map(\.id), [ids[1], ids[3]])
  }

  func testScreenshotsForBatchesExcludesSoftDeletedAndUnknownBatches() {
    let store = StorageManager.shared
    let baseTs = 5_000_000
    guard
      let keptId = store.saveScreenshot(
        segmentPath: "/tmp/dayflow-deleted-kept.mp4",
        frameIndex: 0,
        capturedAt: Date(timeIntervalSince1970: TimeInterval(baseTs)),
        idleSecondsAtCapture: nil
      ),
      let deletedId = store.saveScreenshot(
        segmentPath: "/tmp/dayflow-deleted-gone.mp4",
        frameIndex: 0,
        capturedAt: Date(timeIntervalSince1970: TimeInterval(baseTs + 1)),
        idleSecondsAtCapture: nil
      ),
      let batchId = store.saveBatchWithScreenshots(
        startTs: baseTs, endTs: baseTs + 2, screenshotIds: [keptId, deletedId])
    else {
      XCTFail("Failed to set up screenshots")
      return
    }
    store.markScreenshotsDeleted(segmentPath: "/tmp/dayflow-deleted-gone.mp4")

    let grouped = store.screenshotsForBatches([batchId, 999_999_999])
    XCTAssertEqual(grouped[batchId]?.map(\.id), [keptId])
    XCTAssertNil(grouped[999_999_999])
  }

  func testScreenshotsForBatchesMultiChunk() {
    let store = StorageManager.shared
    let baseTs = 6_000_000
    var batchIds: [Int64] = []

    // 450 batches cross the 400-per-query chunk boundary.
    for i in 0..<450 {
      guard
        let shotId = store.saveScreenshot(
          segmentPath: "/tmp/dayflow-multichunk-\(i).mp4",
          frameIndex: 0,
          capturedAt: Date(timeIntervalSince1970: TimeInterval(baseTs + i)),
          idleSecondsAtCapture: nil
        ),
        let batchId = store.saveBatchWithScreenshots(
          startTs: baseTs + i, endTs: baseTs + i + 1, screenshotIds: [shotId])
      else {
        XCTFail("Failed to create batch \(i)")
        return
      }
      batchIds.append(batchId)
    }

    let grouped = store.screenshotsForBatches(batchIds)
    XCTAssertEqual(grouped.count, 450)
    for batchId in batchIds {
      XCTAssertEqual(grouped[batchId]?.count, 1)
    }
  }
}
