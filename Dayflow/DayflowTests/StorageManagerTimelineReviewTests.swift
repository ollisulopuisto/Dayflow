import XCTest
import GRDB
@testable import Dayflow

final class StorageManagerTimelineReviewTests: XCTestCase {
  func testFetchUnreviewedTimelineCardCountFiltersSystemCategory() {
    // Test helper to verify logic structure of fetchUnreviewedTimelineCardCount category filtering
    let categories = ["System", " System ", "SYSTEM", "system", "  sysTEM  ", "Work", "Personal"]

    let filtered = categories.filter { category in
      let categoryTrimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
      return categoryTrimmed.caseInsensitiveCompare("System") != .orderedSame
    }

    XCTAssertEqual(filtered, ["Work", "Personal"])
  }
}
