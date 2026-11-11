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

  func testWeekWindowCoversTheActualViewportWithLessOverscan() {
    for height in [CGFloat(240), 600, 1_200] {
      for offset in stride(from: CGFloat(0), through: 3_000, by: 17) {
        let bucket = TimelineCardWindow.bucket(layerMinY: -offset)
        let range = TimelineCardWindow.range(bucket: bucket, viewportHeight: height, overscan: 100)
        XCTAssertLessThanOrEqual(range.lowerBound, offset)
        XCTAssertGreaterThanOrEqual(range.upperBound, offset + height)
        XCTAssertEqual(range.upperBound - range.lowerBound, height + 500)
      }
    }
  }

  func testWeekScrollOffsetComesFromPaneSpaceFrames() {
    // At rest the cards layer's top edge sits exactly at the scroll viewport's top edge.
    XCTAssertEqual(
      TimelineCardWindow.weekScrollOffset(cardsLayerTopInPane: 240, viewportTopInPane: 240), 0)
    // Scrolling down moves the layer's pane-space top edge up by the scrolled amount.
    XCTAssertEqual(
      TimelineCardWindow.weekScrollOffset(cardsLayerTopInPane: -960, viewportTopInPane: 240), 1200)
    // Rubber-banding above the top clamps to zero instead of going negative.
    XCTAssertEqual(
      TimelineCardWindow.weekScrollOffset(cardsLayerTopInPane: 260, viewportTopInPane: 240), 0)
  }

  /// Regression: the week grid's card window must be driven by "TimelinePane"-space geometry,
  /// which moves during scrolling on macOS. Measuring the offset in the ScrollView's own
  /// coordinate space never updated, pinned the bucket to 0, and dropped every card below the
  /// initial band (the whole grid after mid-afternoon). Whatever the pane baseline, the
  /// resulting window must cover the whole viewport at every scroll offset.
  func testWeekWindowDrivenByPaneFramesCoversTheViewport() {
    let paneBaseline: CGFloat = 240  // header etc. above the scroll viewport, in pane space
    for height in [CGFloat(240), 600, 1_200] {
      for offset in stride(from: CGFloat(0), through: 3_000, by: 17) {
        let cardsLayerTop = paneBaseline - offset
        let scrollOffset = TimelineCardWindow.weekScrollOffset(
          cardsLayerTopInPane: cardsLayerTop, viewportTopInPane: paneBaseline)
        XCTAssertEqual(scrollOffset, offset)
        let bucket = TimelineCardWindow.bucket(layerMinY: -scrollOffset)
        let range = TimelineCardWindow.range(bucket: bucket, viewportHeight: height, overscan: 100)
        XCTAssertLessThanOrEqual(range.lowerBound, offset, "offset \(offset)")
        XCTAssertGreaterThanOrEqual(range.upperBound, offset + height, "offset \(offset)")
      }
    }
  }
}
