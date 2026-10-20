import XCTest
@testable import Dayflow

final class TimelineClipboardFormatterTests: XCTestCase {
  func testFormattedRangeWithValidStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "11:00 AM"),
      "10:00 AM – 11:00 AM"
    )
  }

  func testFormattedRangeWithEmptyStart() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "", end: "11:00 AM"),
      "11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "   ", end: "11:00 AM"),
      "11:00 AM"
    )
  }

  func testFormattedRangeWithEmptyEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: ""),
      "10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "   "),
      "10:00 AM"
    )
  }

  func testFormattedRangeWithEmptyStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "", end: ""),
      ""
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "   ", end: "  \n "),
      ""
    )
  }

  func testFormattedRangeWithWhitespacePadding() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "  10:00 AM  ", end: "  11:00 AM  "),
      "10:00 AM – 11:00 AM"
    )
  }
}
