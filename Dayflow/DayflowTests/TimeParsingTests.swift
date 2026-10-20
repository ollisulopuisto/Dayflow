import XCTest
@testable import Dayflow

final class TimeParsingTests: XCTestCase {
    func testValidTimes() {
        // "h:mm a"
        XCTAssertEqual(parseTimeHMMA(timeString: "9:30 AM"), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "11:59 PM"), 23 * 60 + 59)

        // "hh:mm a"
        XCTAssertEqual(parseTimeHMMA(timeString: "09:30 AM"), 9 * 60 + 30)

        // "h:mma"
        XCTAssertEqual(parseTimeHMMA(timeString: "9:30AM"), 9 * 60 + 30)

        // "hh:mma"
        XCTAssertEqual(parseTimeHMMA(timeString: "09:30AM"), 9 * 60 + 30)
    }

    func testMidnightAndNoon() {
        XCTAssertEqual(parseTimeHMMA(timeString: "12:00 AM"), 0)
        XCTAssertEqual(parseTimeHMMA(timeString: "12:00 PM"), 12 * 60)
        XCTAssertEqual(parseTimeHMMA(timeString: "12:01 AM"), 1)
        XCTAssertEqual(parseTimeHMMA(timeString: "12:01 PM"), 12 * 60 + 1)
    }

    func testCaseInsensitivity() {
        XCTAssertEqual(parseTimeHMMA(timeString: "9:30 am"), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "9:30 aM"), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "9:30 Am"), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "11:59 pm"), 23 * 60 + 59)
    }

    func testWhitespaceAndNewlines() {
        XCTAssertEqual(parseTimeHMMA(timeString: "  9:30 AM  "), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "\n9:30 AM\n"), 9 * 60 + 30)
        XCTAssertEqual(parseTimeHMMA(timeString: "\t9:30 AM\t"), 9 * 60 + 30)
    }

    func testInvalidTimes() {
        XCTAssertNil(parseTimeHMMA(timeString: ""))
        XCTAssertNil(parseTimeHMMA(timeString: "invalid"))
        XCTAssertNil(parseTimeHMMA(timeString: "9:30")) // Missing AM/PM
        XCTAssertNil(parseTimeHMMA(timeString: "25:00 AM")) // Out of bounds hour
        XCTAssertNil(parseTimeHMMA(timeString: "9:60 AM")) // Out of bounds minute
        XCTAssertNil(parseTimeHMMA(timeString: "9-30 AM")) // Wrong separator
        XCTAssertNil(parseTimeHMMA(timeString: "AM 9:30")) // Wrong order
    }
}
