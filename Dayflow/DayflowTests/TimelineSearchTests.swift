import AppKit
import SwiftUI
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

  func testHighlightRangesUseOriginalUnicodeIndicesAndEveryOccurrence() {
    let text = "CAFÉ Cafe\u{301} cafe 🙂 CAFÉ"
    let ranges = TimelineSearch.highlightRanges(in: text, query: "cafe")
    XCTAssertEqual(ranges.map { String(text[$0]) }, ["CAFÉ", "Cafe\u{301}", "cafe", "CAFÉ"])
    XCTAssertTrue(TimelineSearch.highlightRanges(in: text, query: "   ").isEmpty)
  }

  func testHighlightingPreservesMarkdownAndOnlyMarksDisplayedText() throws {
    let input = try AttributedString(markdown: "**Foxy Bear** uses [Café](https://example.com)")
    let result = TimelineSearch.highlighted(input, query: "foxy cafe")
    XCTAssertEqual(String(result.characters), String(input.characters))
    XCTAssertEqual(result.runs.filter { $0.backgroundColor != nil }.count, 2)
    var restored = result
    restored.backgroundColor = nil
    restored.foregroundColor = nil
    XCTAssertEqual(restored, input, "Markdown links and emphasis must survive highlighting")
    XCTAssertEqual(TimelineSearch.highlighted(input, query: " "), input)
    XCTAssertTrue(TimelineSearch.highlighted(input, query: "example.com").runs.allSatisfy {
      $0.backgroundColor == nil
    })
  }

  func testHighlightRangesAllowOverlappingTermsAndSubstringMatches() {
    let text = "Foxy Bear"
    let ranges = TimelineSearch.highlightRanges(in: text, query: "fox foxy bear")
    XCTAssertEqual(ranges.map { String(text[$0]) }, ["Fox", "Foxy", "Bear"])
    XCTAssertEqual(TimelineSearch.highlightRanges(in: "🙂Straße", query: "strasse").count, 1)
  }

  /// Actual AppKit/SwiftUI pixels from the production inspector and month bar.
  /// The fixture is synthetic and contains no user history. Existing test logs
  /// carry the PNG, avoiding additional CI jobs, artifacts or retention.
  @MainActor
  func testNativeSearchRenderingCapture() throws {
    let fixture = activity(id: "search-fixture", start: Date(timeIntervalSince1970: 1_800_000_000),
      end: Date(timeIntervalSince1970: 1_800_001_800), title: "Planning with Foxy Bear",
      summary: "Edited **Foxy Bear** notes at Café Regatta. Text stays selectable.",
      detailedSummary: "Reviewed Foxy Bear recordings and prepared the next episode.")
    let summary = MonthDaySummary(totalSeconds: 100,
      secondsByCategory: ["work": 70, "personal": 30],
      matchingSecondsByCategory: ["work": 25], firstMatchingIDByCategory: ["work": fixture.id])
    let root = VStack(spacing: 16) {
      ActivityCard(activity: fixture, searchQuery: "foxy cafe")
        .environmentObject(AppState.shared)
        .environmentObject(CategoryStore())
        .environmentObject(RetryCoordinator())
        .frame(height: 460)
      MonthCategorySearchBar(summary: summary, searchQuery: "foxy",
        colorForKey: { $0 == "work" ? .orange : .blue }, onSelectMatch: { _ in }, onSelectDay: {})
        .frame(width: 360)
    }
    .padding(20)
    .frame(width: 480, height: 540)
    .background(Color(red: 0.11, green: 0.12, blue: 0.15))
    .environment(\.dayflowTheme, .dark)
    .environment(\.stylePreviewAfter, true)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 480, height: 540)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    XCTAssertGreaterThan(png.count, 1000)
    try png.write(to: URL(fileURLWithPath: "/tmp/dayflow-search-native.png"), options: .atomic)
    window.close()
  }

  private func activity(id: String, start: Date, end: Date, title: String, summary: String = "", detailedSummary: String = "") -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: nil,
      batchId: nil,
      startTime: start,
      endTime: end,
      title: title,
      summary: summary,
      detailedSummary: detailedSummary,
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
