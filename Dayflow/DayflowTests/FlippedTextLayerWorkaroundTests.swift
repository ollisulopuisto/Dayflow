import QuartzCore
import XCTest

@testable import Dayflow

private class MockCGDrawingLayer: CALayer {
  var needsDisplayCallCount = 0

  override func setNeedsDisplay() {
    needsDisplayCallCount += 1
    super.setNeedsDisplay()
  }
}

private class MockPlainLayer: CALayer {
  var needsDisplayCallCount = 0

  override func setNeedsDisplay() {
    needsDisplayCallCount += 1
    super.setNeedsDisplay()
  }
}

final class FlippedTextLayerWorkaroundTests: XCTestCase {

  override func setUp() {
    super.setUp()
    FlippedTextLayerWorkaround.install()
  }

  func testIsSwiftUIDrawingLayer() {
    let drawingLayer = MockCGDrawingLayer()
    let plainLayer = CALayer()

    XCTAssertTrue(FlippedTextLayerWorkaround.isSwiftUIDrawingLayer(drawingLayer))
    XCTAssertFalse(FlippedTextLayerWorkaround.isSwiftUIDrawingLayer(plainLayer))
  }

  func testContentsAreFlippedTriggersSetNeedsDisplayOnDrawingLayer() {
    let layer = MockCGDrawingLayer()
    let initialCount = layer.needsDisplayCallCount

    layer.didChangeValue(forKey: "contentsAreFlipped")

    XCTAssertGreaterThan(layer.needsDisplayCallCount, initialCount)
  }

  func testContentsAreFlippedDoesNotTriggerSetNeedsDisplayOnPlainLayer() {
    let layer = MockPlainLayer()
    let initialCount = layer.needsDisplayCallCount

    layer.didChangeValue(forKey: "contentsAreFlipped")

    XCTAssertEqual(layer.needsDisplayCallCount, initialCount)
  }

  func testOtherPropertyChangesDoNotTriggerSetNeedsDisplay() {
    let layer = MockCGDrawingLayer()
    let initialCount = layer.needsDisplayCallCount

    layer.didChangeValue(forKey: "bounds")
    layer.didChangeValue(forKey: "position")

    XCTAssertEqual(layer.needsDisplayCallCount, initialCount)
  }
}
