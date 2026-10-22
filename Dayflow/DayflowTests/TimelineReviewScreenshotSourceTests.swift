import XCTest

@testable import Dayflow

final class TimelineReviewScreenshotSourceTests: XCTestCase {
  func testFallsBackToActivityBoundsWhenCardBoundsHoldNoScreenshots() async {
    let store = FakeScreenshotStore()
    store.cards[1] = card(id: 1, startTs: 0, endTs: 100)
    store.screenshots = [shot(id: 10, at: 250), shot(id: 11, at: 260)]
    let source = TimelineReviewScreenshotSource(storage: store)

    let result = await source.screenshots(for: activity(recordId: 1, startTs: 200, endTs: 300))

    XCTAssertEqual(result.map(\.id), [10, 11])
  }

  func testPrefersCardBoundsWhenTheyHoldScreenshots() async {
    let store = FakeScreenshotStore()
    store.cards[1] = card(id: 1, startTs: 0, endTs: 100)
    store.screenshots = [shot(id: 10, at: 50), shot(id: 11, at: 250)]
    let source = TimelineReviewScreenshotSource(storage: store)

    let result = await source.screenshots(for: activity(recordId: 1, startTs: 200, endTs: 300))

    XCTAssertEqual(result.map(\.id), [10])
  }

  func testPrefetchedDayAnswersActivityRangeWithoutDatabaseQueries() async {
    let store = FakeScreenshotStore()
    store.screenshots = [shot(id: 10, at: 250), shot(id: 11, at: 260), shot(id: 12, at: 900)]
    let source = TimelineReviewScreenshotSource(storage: store)
    await source.prefetchDay(startTs: 0, endTs: 1000)
    store.resetCounts()

    let result = await source.screenshots(for: activity(recordId: nil, startTs: 200, endTs: 300))

    XCTAssertEqual(result.map(\.id), [10, 11])
    XCTAssertEqual(store.rangeQueryCount, 0)
  }

  func testPrefetchedDayWithNoScreenshotsInRangeDoesNotQueryAgain() async {
    let store = FakeScreenshotStore()
    store.cards[1] = card(id: 1, startTs: 0, endTs: 100)
    store.screenshots = [shot(id: 12, at: 900)]
    let source = TimelineReviewScreenshotSource(storage: store)
    await source.prefetchDay(startTs: 0, endTs: 1000)
    store.resetCounts()

    let result = await source.screenshots(for: activity(recordId: 1, startTs: 200, endTs: 300))

    XCTAssertEqual(result, [])
    XCTAssertEqual(store.rangeQueryCount, 0)
  }

  func testRangeOutsidePrefetchedDayFallsBackToDatabase() async {
    let store = FakeScreenshotStore()
    store.screenshots = [shot(id: 20, at: 1_500)]
    let source = TimelineReviewScreenshotSource(storage: store)
    await source.prefetchDay(startTs: 0, endTs: 1000)
    store.resetCounts()

    let result = await source.screenshots(for: activity(recordId: nil, startTs: 1_400, endTs: 1_600))

    XCTAssertEqual(result.map(\.id), [20])
    XCTAssertEqual(store.rangeQueryCount, 1)
  }

  func testCardBoundsAreLookedUpOncePerRecord() async {
    let store = FakeScreenshotStore()
    store.cards[1] = card(id: 1, startTs: 0, endTs: 100)
    store.screenshots = [shot(id: 10, at: 50)]
    let source = TimelineReviewScreenshotSource(storage: store)
    let item = activity(recordId: 1, startTs: 200, endTs: 300)

    _ = await source.screenshots(for: item)
    _ = await source.screenshots(for: item)

    XCTAssertEqual(store.cardLookupCount, 1)
  }

  func testDayCacheBinarySearchKeepsBoundsInclusive() async {
    let store = FakeScreenshotStore()
    store.screenshots = [
      shot(id: 1, at: 100), shot(id: 2, at: 200), shot(id: 3, at: 200), shot(id: 4, at: 300),
      shot(id: 5, at: 301),
    ]
    let source = TimelineReviewScreenshotSource(storage: store)
    await source.prefetchDay(startTs: 0, endTs: 1000)

    let result = await source.screenshots(for: activity(recordId: nil, startTs: 200, endTs: 300))

    XCTAssertEqual(result.map(\.id), [2, 3, 4])
  }

  private func card(id: Int64, startTs: Int, endTs: Int) -> TimelineCardWithTimestamps {
    TimelineCardWithTimestamps(
      id: id, startTimestamp: "", endTimestamp: "", startTs: startTs, endTs: endTs,
      category: "", subcategory: "", title: "", summary: "", detailedSummary: "",
      day: "", distractions: nil, videoSummaryURL: nil)
  }

  private func shot(id: Int64, at capturedAt: Int) -> Screenshot {
    Screenshot(
      id: id, capturedAt: capturedAt, filePath: "", fileSize: nil,
      idleSecondsAtCapture: nil, isDeleted: false)
  }

  private func activity(recordId: Int64?, startTs: Int, endTs: Int) -> TimelineActivity {
    TimelineActivity(
      id: "activity-\(startTs)",
      recordId: recordId,
      batchId: nil,
      startTime: Date(timeIntervalSince1970: TimeInterval(startTs)),
      endTime: Date(timeIntervalSince1970: TimeInterval(endTs)),
      title: "",
      summary: "",
      detailedSummary: "",
      category: "",
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: false
    )
  }
}

private final class FakeScreenshotStore: TimelineReviewScreenshotStore, @unchecked Sendable {
  var cards: [Int64: TimelineCardWithTimestamps] = [:]
  var screenshots: [Screenshot] = []
  private(set) var rangeQueryCount = 0
  private(set) var cardLookupCount = 0

  func resetCounts() {
    rangeQueryCount = 0
    cardLookupCount = 0
  }

  func fetchTimelineCard(byId id: Int64) -> TimelineCardWithTimestamps? {
    cardLookupCount += 1
    return cards[id]
  }

  func fetchScreenshotsInTimeRange(startTs: Int, endTs: Int) -> [Screenshot] {
    rangeQueryCount += 1
    return screenshots
      .filter { $0.capturedAt >= startTs && $0.capturedAt <= endTs }
      .sorted { $0.capturedAt < $1.capturedAt }
  }
}
