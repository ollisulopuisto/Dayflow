//
//  ChangelogNotes.swift
//  Dayflow
//
//  Parses the bundled Keep-a-Changelog CHANGELOG.md into per-version bullet
//  lists for the What's New modal. The bundled copy is kept in sync with the
//  repository-root CHANGELOG.md; ChangelogNotesTests fail if they drift.
//

import Foundation

struct ChangelogSection: Equatable {
  let version: String
  let items: [String]
}

enum ChangelogNotes {
  /// Released sections from the bundled changelog, newest first. Returns an
  /// empty list when the resource is missing - a packaging gap is silence,
  /// not a crash.
  static func load(bundle: Bundle = .main) -> [ChangelogSection] {
    guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return parse(text)
  }

  /// Sections are introduced by "## [X.Y.Z] - <date>" headings; "## [Unreleased]"
  /// and non-release headings are skipped, as are "###" subsections (their "- "
  /// bullets still belong to the enclosing release).
  static func parse(_ markdown: String) -> [ChangelogSection] {
    var sections: [ChangelogSection] = []
    var currentVersion: String?
    var items: [String] = []

    func flush() {
      if let version = currentVersion, !items.isEmpty {
        sections.append(ChangelogSection(version: version, items: items))
      }
    }

    for line in markdown.components(separatedBy: .newlines) {
      if line.hasPrefix("## ") {
        flush()
        currentVersion = nil
        items = []
        guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"), open < close
        else { continue }
        let name = String(line[line.index(after: open)..<close])
        if name != "Unreleased", !name.isEmpty {
          currentVersion = name
        }
      } else if line.hasPrefix("### ") {
        continue
      } else if currentVersion != nil, line.hasPrefix("- ") {
        let item = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if !item.isEmpty { items.append(item) }
      }
    }
    flush()
    return sections
  }

  /// Numeric per-segment compare: 2.7.9 < 2.7.22, and a missing trailing
  /// segment counts as zero (2.7.22 < 2.7.22.1). Returns -1, 0 or 1.
  static func compareVersions(_ a: String, _ b: String) -> Int {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
      let va = i < pa.count ? pa[i] : 0
      let vb = i < pb.count ? pb[i] : 0
      if va != vb { return va < vb ? -1 : 1 }
    }
    return 0
  }

  /// Sections newer than `lastSeen`, up to and including `current`, newest
  /// first. A `lastSeen` of "" means the full released history.
  static func sectionsSince(_ sections: [ChangelogSection], current: String, lastSeen: String)
    -> [ChangelogSection]
  {
    sections.filter {
      compareVersions($0.version, lastSeen) > 0 && compareVersions($0.version, current) <= 0
    }
  }
}
