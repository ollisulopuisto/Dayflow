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
}
