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

  func testFormattedRangeWithNewlineAndTabWhitespace() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\t10:00 AM\n", end: "\r\n11:00 AM\t"),
      "10:00 AM – 11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\n\t  ", end: "11:00 AM"),
      "11:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "\r\n\t"),
      "10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "\r\n\t ", end: "\n\n\t"),
      ""
    )
  }

  func testFormattedRangeWithIdenticalStartAndEnd() {
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: "10:00 AM", end: "10:00 AM"),
      "10:00 AM – 10:00 AM"
    )
    XCTAssertEqual(
      TimelineClipboardFormatter.formattedRange(start: " 10:00 AM \n", end: "\t10:00 AM "),
      "10:00 AM – 10:00 AM"
    )
  }
}
