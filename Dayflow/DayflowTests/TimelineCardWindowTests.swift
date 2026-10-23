import XCTest

@testable import Dayflow

final class TimelineCardWindowTests: XCTestCase {
  func testBucketIsZeroAtTheTopAndNeverNegative() {
    XCTAssertEqual(TimelineCardWindow.bucket(layerMinY: 120), 0)
    XCTAssertEqual(TimelineCardWindow.bucket(layerMinY: 0), 0)
  }

  func testBucketAdvancesEveryBucketSizeOfScroll() {
    let size = TimelineCardWindow.bucketSize
    XCTAssertEqual(TimelineCardWindow.bucket(layerMinY: -(size - 1)), 0)
    XCTAssertEqual(TimelineCardWindow.bucket(layerMinY: -size), 1)
    XCTAssertEqual(TimelineCardWindow.bucket(layerMinY: -(size * 3 + 5)), 3)
  }

  func testCardsNearTheViewportAreKeptAndFarOnesDropped() {
    let range = TimelineCardWindow.range(bucket: 4, viewportHeight: 800)
    let top = range.lowerBound
    XCTAssertTrue(TimelineCardWindow.isVisible(y: top + 10, height: 20, in: range))
    XCTAssertTrue(TimelineCardWindow.isVisible(y: top - 50, height: 80, in: range))  // overlaps the top edge
    XCTAssertFalse(TimelineCardWindow.isVisible(y: top - 200, height: 20, in: range))
    XCTAssertFalse(TimelineCardWindow.isVisible(y: range.upperBound + 5, height: 20, in: range))
  }

  /// A scroll inside one bucket must not change what is drawn.
  func testWindowIsStableWithinABucket() {
    XCTAssertEqual(
      TimelineCardWindow.range(bucket: 2, viewportHeight: 800),
      TimelineCardWindow.range(bucket: 2, viewportHeight: 800))
    let viewport = TimelineCardWindow.viewportHeight(windowContentHeight: nil)
    XCTAssertGreaterThanOrEqual(viewport, 800)
  }

  func testTheViewportCoversTheTrueVisibleBand() {
    // True top of the viewport in layer coordinates is scroll offset; the bucket only sees
    // offset minus the header above the layer, so allow for a 200 pt header.
    for offset in stride(from: CGFloat(0), through: 5_000, by: 37) {
      let bucket = TimelineCardWindow.bucket(layerMinY: -(offset - 200))
      let range = TimelineCardWindow.range(bucket: bucket, viewportHeight: 900)
      XCTAssertLessThanOrEqual(range.lowerBound, offset, "offset \(offset)")
      XCTAssertGreaterThanOrEqual(range.upperBound, offset + 900, "offset \(offset)")
    }
  }
}
