import AppKit
import SwiftUI

/// Free-text search over timeline cards. Every whitespace-separated term has to appear in at
/// least one field (title, summaries, category, app or site), ignoring case and diacritics.
enum TimelineSearch {
  static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  static func terms(_ query: String) -> [String] {
    fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  static func matches(terms: [String], fields: [String]) -> Bool {
    guard !terms.isEmpty else { return true }
    let folded = fields.map(fold)
    return terms.allSatisfy { term in folded.contains { $0.contains(term) } }
  }

  static func fields(of activity: TimelineActivity) -> [String] {
    [
      activity.title, activity.summary, activity.detailedSummary, activity.category,
      activity.subcategory, activity.appSites?.primary, activity.appSites?.secondary,
    ].compactMap { $0 }
  }

  static func matches(terms: [String], activity: TimelineActivity) -> Bool {
    matches(terms: terms, fields: fields(of: activity))
  }

  /// The ids of matching activities, or nil when there is no query (nothing is dimmed).
  static func matchingIDs(terms: [String], activities: [TimelineActivity]) -> Set<String>? {
    guard !terms.isEmpty else { return nil }
    return Set(activities.filter { matches(terms: terms, activity: $0) }.map(\.id))
  }
}

/// ⌘← and ⌘→ step the timeline. In a text field they keep their editing meaning instead.
enum TimelineStep {
  static func textEditingSelector(for delta: Int) -> Selector {
    delta < 0
      ? #selector(NSResponder.moveToBeginningOfLine(_:))
      : #selector(NSResponder.moveToEndOfLine(_:))
  }
}

struct TimelineSearchField: View {
  @Binding var text: String
  var isFocused: FocusState<Bool>.Binding
  @Environment(\.dayflowTheme) private var theme

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11))
        .foregroundColor(theme.textTertiary)
      TextField(String(localized: "Search"), text: $text)
        .textFieldStyle(.plain)
        .font(.custom("Figtree", size: 12))
        .focused(isFocused)
        .onExitCommand {
          text = ""
          isFocused.wrappedValue = false
        }
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundColor(theme.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Clear search"))
      }
    }
    .padding(.horizontal, 8)
    .frame(width: 170, height: 24)
    .background(RoundedRectangle(cornerRadius: 6).fill(theme.controlFill))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.controlBorder, lineWidth: 0.5))
  }
}
