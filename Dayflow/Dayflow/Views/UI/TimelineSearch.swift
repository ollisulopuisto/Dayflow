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

  static func statistics(query: String, activities: [TimelineActivity]) -> TimelineSearchStats? {
    let searchTerms = terms(query)
    guard !searchTerms.isEmpty else { return nil }
    let matchedActivities = activities.filter { TimelineSearch.matches(terms: searchTerms, activity: $0) }
    guard let first = matchedActivities.map(\.startTime).min(), let last = matchedActivities.map(\.endTime).max() else {
      return TimelineSearchStats(matchCount: 0, totalDuration: 0, firstMatch: nil, lastMatch: nil)
    }
    let duration = matchedActivities.reduce(0.0) { total, activity in
      total + max(0, activity.endTime.timeIntervalSince(activity.startTime))
    }
    return TimelineSearchStats(
      matchCount: matchedActivities.count,
      totalDuration: duration,
      firstMatch: first,
      lastMatch: last
    )
  }
}

struct TimelineSearchStats: Equatable, Sendable {
  let matchCount: Int
  let totalDuration: TimeInterval
  let firstMatch: Date?
  let lastMatch: Date?

  var displayText: String {
    guard matchCount > 0, let firstMatch, let lastMatch else {
      return String(localized: "No matches")
    }
    let formatter = Self.timeFormatter
    return "\(matchCount) · \(Self.durationText(totalDuration)) · \(formatter.string(from: firstMatch))–\(formatter.string(from: lastMatch))"
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeStyle = .none
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static func durationText(_ duration: TimeInterval) -> String {
    let minutes = max(0, Int((duration / 60).rounded()))
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder)m" }
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
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
  var stats: TimelineSearchStats? = nil
  @Environment(\.dayflowTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
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

      if !TimelineSearch.terms(text).isEmpty, let stats {
        Text(stats.displayText)
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .foregroundColor(theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.leading, 4)
          .frame(width: 170, alignment: .leading)
          .help(stats.displayText)
          .accessibilityLabel("Search results: \(stats.displayText)")
      }
    }
    .frame(width: 170, alignment: .leading)
  }
}

extension MainView {
  func refreshTimelineSearchStats() {
    let query = timelineSearchText
    guard !TimelineSearch.terms(query).isEmpty else {
      timelineSearchStats = nil
      timelineSearchStatsRequestID += 1
      return
    }

    timelineSearchStatsRequestID += 1
    let requestID = timelineSearchStatsRequestID
    let selectedDate = self.selectedDate
    let mode = timelineMode

    Task {
      let stats = await Task.detached(priority: .userInitiated) {
        let activities: [TimelineActivity]
        switch mode {
        case .hour, .day:
          activities = TimelineActivityLoader.dayPayload(for: selectedDate).activities
        case .week:
          activities = TimelineActivityLoader.activities(in: TimelineWeekRange.containing(selectedDate))
        case .month:
          activities = TimelineActivityLoader.activities(in: TimelineMonthRange.containing(selectedDate))
        }
        return TimelineSearch.statistics(query: query, activities: activities)
      }.value

      guard requestID == timelineSearchStatsRequestID,
        query == timelineSearchText,
        selectedDate == self.selectedDate,
        mode == timelineMode
      else { return }
      timelineSearchStats = stats
    }
  }
}
