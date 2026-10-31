//
//  ChangelogNotesTests.swift
//  DayflowTests
//
//  Pins the What's New changelog parsing and upgrade semantics against a
//  fixture and against the real repository changelog.
//

import XCTest
@testable import Dayflow

final class ChangelogNotesTests: XCTestCase {

  private static let fixture = """
    # Changelog

    ## [Unreleased]

    ### Fixed
    - Unreleased work in progress.

    ## [2.7.22] - 2026-10-30

    ### Performance
    - Reduce memory footprint.
    - Integrate upstream PR 407 memory reductions.

    ### Fixed
    - Fix duplicate FrameStore.close() redeclaration.

    ## [2.7.21] - 2026-10-29

    ### Changed
    - Explicitly close cached HEVC frame readers on eviction.

    ## [2.7.9] - 2026-09-01

    - Older single-section release.
    """

  func testParsesReleasedSectionsNewestFirstSkippingUnreleased() {
    let sections = ChangelogNotes.parse(Self.fixture)
    XCTAssertEqual(sections.map(\.version), ["2.7.22", "2.7.21", "2.7.9"])
    XCTAssertEqual(
      sections[0].items,
      [
        "Reduce memory footprint.",
        "Integrate upstream PR 407 memory reductions.",
        "Fix duplicate FrameStore.close() redeclaration.",
      ])
    XCTAssertFalse(sections.contains { $0.version == "Unreleased" })
  }

  func testCompareVersionsIsNumericPerSegment() {
    XCTAssertEqual(ChangelogNotes.compareVersions("2.7.9", "2.7.22"), -1)
    XCTAssertEqual(ChangelogNotes.compareVersions("2.7.22", "2.7.22"), 0)
    XCTAssertEqual(ChangelogNotes.compareVersions("2.7.22", "2.7.9"), 1)
    XCTAssertEqual(ChangelogNotes.compareVersions("2.7.22", "2.7.22.1"), -1)
  }

  func testSectionsSinceShowsOnlyTheUpgradeWindow() {
    let sections = ChangelogNotes.parse(Self.fixture)
    let pending = ChangelogNotes.sectionsSince(sections, current: "2.7.22", lastSeen: "2.7.9")
    XCTAssertEqual(pending.map(\.version), ["2.7.22", "2.7.21"])
    // A downgrade shows nothing.
    XCTAssertTrue(
      ChangelogNotes.sectionsSince(sections, current: "2.7.9", lastSeen: "2.7.22").isEmpty)
    // Empty lastSeen means full history.
    XCTAssertEqual(
      ChangelogNotes.sectionsSince(sections, current: "2.7.22", lastSeen: "").count, 3)
  }

  func testRealRepositoryChangelogParses() {
    // <repo>/Dayflow/DayflowTests/ChangelogNotesTests.swift -> repo root
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repoRoot.appendingPathComponent("CHANGELOG.md")
    let bundled = repoRoot.appendingPathComponent("Dayflow/Dayflow/CHANGELOG.md")
    guard let rootText = try? String(contentsOf: root, encoding: .utf8) else {
      XCTFail("repository CHANGELOG.md unreadable")
      return
    }
    let sections = ChangelogNotes.parse(rootText)
    XCTAssertTrue(sections.count >= 5, "expected the real release history, got \(sections.count)")
    XCTAssertTrue(sections.allSatisfy { !$0.items.isEmpty })
    XCTAssertFalse(sections.contains { $0.version == "Unreleased" })

    // The bundled copy the app ships must not drift from the source of truth.
    XCTAssertEqual(
      try? String(contentsOf: bundled, encoding: .utf8), rootText,
      "Dayflow/Dayflow/CHANGELOG.md is out of sync with the repository CHANGELOG.md")
  }
}
