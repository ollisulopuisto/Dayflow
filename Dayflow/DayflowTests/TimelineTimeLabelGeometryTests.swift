import XCTest

@testable import Dayflow

final class TimelineTimeLabelGeometryTests: XCTestCase {
  func testOneFramePerHourStackedByHourHeight() {
    let column = CGRect(x: 10, y: 100, width: 50, height: 240)
    let frames = TimelineTimeLabelGeometry.frames(
      column: column, count: 3, hourHeight: 80, labelHeight: 14, yOffset: -8)
    XCTAssertEqual(
      frames,
      [
        CGRect(x: 10, y: 92, width: 50, height: 14),
        CGRect(x: 10, y: 172, width: 50, height: 14),
        CGRect(x: 10, y: 252, width: 50, height: 14),
      ])
  }

  func testEmptyColumnGivesNoFrames() {
    XCTAssertEqual(
      TimelineTimeLabelGeometry.frames(
        column: .zero, count: 0, hourHeight: 80, labelHeight: 14, yOffset: 0), [])
  }

  /// The footer fade must read the same from computed frames as from measured ones.
  func testFadeLevelFromComputedFrames() {
    let frames = TimelineTimeLabelGeometry.frames(
      column: CGRect(x: 0, y: 0, width: 50, height: 160), count: 2, hourHeight: 80,
      labelHeight: 14, yOffset: 0)
    let overlapping = CGRect(x: 0, y: 80, width: 50, height: 14)
    XCTAssertEqual(
      MainView.weeklyHoursFadeLevel(labelFrames: frames, hoursFrame: overlapping, fadeDistance: 14),
      0)
    let clear = CGRect(x: 0, y: 40, width: 50, height: 14)
    XCTAssertEqual(
      MainView.weeklyHoursFadeLevel(labelFrames: frames, hoursFrame: clear, fadeDistance: 14), 1)
  }
}
