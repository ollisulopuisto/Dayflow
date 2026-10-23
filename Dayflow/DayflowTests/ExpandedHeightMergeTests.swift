import XCTest

@testable import Dayflow

final class ExpandedHeightMergeTests: XCTestCase {
  func testNewValuesAreAddedToWhatIsKnown() {
    let merged = ExpandedHeightMerge.merged(current: ["a": 30], incoming: ["b": 44])
    XCTAssertEqual(merged, ["a": 30, "b": 44])
  }

  func testIncomingValueReplacesTheOldOne() {
    let merged = ExpandedHeightMerge.merged(current: ["a": 30], incoming: ["a": 42])
    XCTAssertEqual(merged, ["a": 42])
  }

  /// Nothing to write means no @State assignment and no re-render.
  func testNilWhenNothingChanges() {
    XCTAssertNil(ExpandedHeightMerge.merged(current: ["a": 30], incoming: ["a": 30]))
    XCTAssertNil(ExpandedHeightMerge.merged(current: ["a": 30], incoming: [:]))
  }
}
