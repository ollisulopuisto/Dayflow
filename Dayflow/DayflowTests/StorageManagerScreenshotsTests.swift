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
}
