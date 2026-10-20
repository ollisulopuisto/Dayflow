import XCTest
@testable import Dayflow

final class DebugLogFormatterTests: XCTestCase {

    func testCleanedWithValidString() {
        let input = "Hello World"
        XCTAssertEqual(DebugLogFormatter.cleaned(input), "Hello World")
    }

    func testCleanedWithEmptyString() {
        XCTAssertNil(DebugLogFormatter.cleaned(""))
    }

    func testCleanedWithWhitespaceString() {
        XCTAssertNil(DebugLogFormatter.cleaned("   "))
    }

    func testCleanedWithNewlinesAndSpaces() {
        let input = "  Hello \n \n World  "
        XCTAssertEqual(DebugLogFormatter.cleaned(input), "Hello World")
    }

    func testCleanedWithMultipleSpaces() {
        let input = "Hello     World"
        XCTAssertEqual(DebugLogFormatter.cleaned(input), "Hello World")
    }

    func testCleanedWithNilString() {
        XCTAssertNil(DebugLogFormatter.cleaned(nil))
    }
}
