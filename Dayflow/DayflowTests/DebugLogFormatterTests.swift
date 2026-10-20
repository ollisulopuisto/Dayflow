import XCTest
@testable import Dayflow

final class DebugLogFormatterTests: XCTestCase {

  func testFormatPayloadWithValidJSON() throws {
    let rawJSON = "{\"name\": \"Alice\", \"age\": 30}"
    let formatted = DebugLogFormatter.formatPayload(rawJSON)

    // We expect it to be pretty printed
    let unwrappedFormatted = try XCTUnwrap(formatted)
    // Checking format features
    XCTAssertTrue(unwrappedFormatted.contains("{\n"))
    XCTAssertTrue(unwrappedFormatted.contains("\"name\" : \"Alice\""))
    XCTAssertTrue(unwrappedFormatted.contains("\"age\" : 30"))
  }

  func testFormatPayloadWithInvalidJSON() {
    let rawText = "This is not JSON."
    let formatted = DebugLogFormatter.formatPayload(rawText)

    // It should just return the trimmed string
    XCTAssertEqual(formatted, "This is not JSON.")
  }

  func testFormatPayloadWithEmptyString() {
    XCTAssertNil(DebugLogFormatter.formatPayload(""))
    XCTAssertNil(DebugLogFormatter.formatPayload("   "))
    XCTAssertNil(DebugLogFormatter.formatPayload("\n"))
  }

  func testFormatPayloadWithNil() {
    XCTAssertNil(DebugLogFormatter.formatPayload(nil))
  }
}
