import XCTest

@testable import Dayflow

final class TimelineSearchTests: XCTestCase {
  func testEmptyQueryMatchesEverything() {
    XCTAssertTrue(TimelineSearch.matches(terms: TimelineSearch.terms("   "), fields: ["anything"]))
    XCTAssertTrue(TimelineSearch.matches(terms: [], fields: []))
  }

  func testMatchIgnoresCaseAndDiacritics() {
    let terms = TimelineSearch.terms("cafe")
    XCTAssertTrue(TimelineSearch.matches(terms: terms, fields: ["Planning at CAFÉ Regatta"]))
    XCTAssertTrue(TimelineSearch.matches(terms: TimelineSearch.terms("ÄÄNI"), fields: ["aani editing"]))
  }

  func testEveryTermMustMatchSomeField() {
    let fields = ["Writing report", "Research", "docs.google.com"]
    XCTAssertTrue(
      TimelineSearch.matches(terms: TimelineSearch.terms("report google"), fields: fields))
    XCTAssertFalse(
      TimelineSearch.matches(terms: TimelineSearch.terms("report figma"), fields: fields))
  }

  func testSubstringMatchesInsideAWord() {
    XCTAssertTrue(TimelineSearch.matches(terms: ["roadm"], fields: ["Roadmap review"]))
  }

  func testStatisticsCountMatchesSumDurationAndShowTimeRange() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let activities = [
      activity(id: "one", start: start, end: start.addingTimeInterval(30 * 60), title: "Planning"),
      activity(id: "two", start: start.addingTimeInterval(2 * 60 * 60), end: start.addingTimeInterval(3 * 60 * 60), title: "Planning follow-up"),
      activity(id: "three", start: start, end: start.addingTimeInterval(10 * 60), title: "Email"),
    ]

    let stats = TimelineSearch.statistics(query: "planning", activities: activities)

    XCTAssertEqual(stats?.matchCount, 2)
    XCTAssertEqual(stats?.totalDuration, 90 * 60)
    XCTAssertEqual(stats?.firstMatch, start)
    XCTAssertEqual(stats?.lastMatch, start.addingTimeInterval(3 * 60 * 60))
  }

  func testStatisticsReturnNoMatchesAndIgnoreEmptyQuery() {
    let item = activity(
      id: "one", start: Date(), end: Date().addingTimeInterval(60), title: "Planning")

    XCTAssertEqual(TimelineSearch.statistics(query: "missing", activities: [item])?.matchCount, 0)
    XCTAssertNil(TimelineSearch.statistics(query: "  ", activities: [item]))
  }

  func testDoubleClickFacetShowsOnlyThatCategoryAndTogglesBackToAll() {
    let allKeys: Set<String> = ["work", "personal", "idle"]
    let onlyWork = CategoryFacetSelection.doubleClick(
      key: "work", allKeys: allKeys, mutedKeys: [])

    XCTAssertEqual(onlyWork, ["personal", "idle"])
    XCTAssertEqual(
      CategoryFacetSelection.doubleClick(key: "work", allKeys: allKeys, mutedKeys: onlyWork), [])
  }

  private func activity(id: String, start: Date, end: Date, title: String) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: nil,
      batchId: nil,
      startTime: start,
      endTime: end,
      title: title,
      summary: "",
      detailedSummary: "",
      category: "Work",
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: false
    )
  }
}
