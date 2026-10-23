import AppKit
import XCTest

@testable import Dayflow

final class TimelineStepTests: XCTestCase {
  /// In a text field the shortcut keeps its normal meaning: start and end of the line.
  func testTextFieldFallbackMovesToLineEnds() {
    XCTAssertEqual(
      TimelineStep.textEditingSelector(for: -1), #selector(NSResponder.moveToBeginningOfLine(_:)))
    XCTAssertEqual(
      TimelineStep.textEditingSelector(for: 1), #selector(NSResponder.moveToEndOfLine(_:)))
  }
}
