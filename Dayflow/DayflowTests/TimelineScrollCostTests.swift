import XCTest

@testable import Dayflow

final class TimelineScrollCostTests: XCTestCase {
  func testFooterOverlapMatchesRectIntersection() {
    let footer = CGRect(x: 0, y: 100, width: 300, height: 20)
    for (y, height) in [(0.0, 50.0), (90.0, 20.0), (110.0, 5.0), (119.0, 40.0), (120.0, 10.0),
      (50.0, 50.0), (130.0, 10.0)]
    {
      let card = CGRect(x: 0, y: y, width: 300, height: height)
      XCTAssertEqual(
        TimelineFooterOverlap.overlaps(cardY: y, height: height, footer: footer),
        card.intersects(footer), "card y=\(y) h=\(height)")
    }
  }

  func testEdgeGlowLayersAreCheapAndBounded() {
    let layers = CardEdgeGlowSpec.layers
    XCTAssertEqual(layers.map(\.width), layers.map(\.width).sorted())
    XCTAssertLessThanOrEqual(layers.reduce(0) { $0 + $1.opacity }, 0.6)
    XCTAssertEqual(layers.count, 3)
  }
}
