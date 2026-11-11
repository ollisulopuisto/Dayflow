import AppKit
import SwiftUI

/// Per-day totals shown in one cell of the month grid.
struct MonthDaySummary: Equatable {
  var totalSeconds: TimeInterval = 0
  /// Seconds per category filter key, plus the display name for colour lookup.
  var secondsByCategory: [String: TimeInterval] = [:]
  var matchingSecondsByCategory: [String: TimeInterval] = [:]
  var firstMatchingIDByCategory: [String: String] = [:]
}

enum MonthTimelineSummary {
  /// True when the whole calendar day starts after `now`, so it cannot have activity yet.
  static func isFutureDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
    calendar.startOfDay(for: date) > now
  }

  /// Groups activities by their 4 AM-bounded day string and sums time per category.
  /// Idle time is left out of the totals.
  ///
  /// Activities are split across every 4 AM→4 AM day window they overlap, and
  /// overlapping coverage within a day is counted once.
  static func summarize(
    _ activities: [TimelineActivity],
    mutedCategoryKeys: Set<String> = [],
    idleCategoryKeys: Set<String> = [],
    searchTerms: [String] = []
  ) -> [String: MonthDaySummary] {
    var activityByDay: [String: [(start: Int, end: Int, key: String, matches: Bool, id: String, originalStart: Date)]] = [:]
    for activity in activities {
      let key = categoryFilterKey(activity.category)
      if idleCategoryKeys.contains(key) || mutedCategoryKeys.contains(key) { continue }
      let matches = !searchTerms.isEmpty && TimelineSearch.matches(terms: searchTerms, activity: activity)

      var cursor = activity.startTime
      while cursor < activity.endTime {
        let dayInfo = cursor.getDayInfoFor4AMBoundary()
        let pieceEnd = min(activity.endTime, dayInfo.endOfDay)
        guard pieceEnd > cursor else { break }
        activityByDay[dayInfo.dayString, default: []].append((
          start: Int(cursor.timeIntervalSince(dayInfo.startOfDay)),
          end: Int(pieceEnd.timeIntervalSince(dayInfo.startOfDay)),
          key: key, matches: matches, id: activity.id, originalStart: activity.startTime
        ))
        cursor = pieceEnd
      }
    }

    var result: [String: MonthDaySummary] = [:]
    for (day, dayActivities) in activityByDay {
      var summary = MonthDaySummary()
      // Assign each covered slice to one category only. Earlier-starting cards
      // take precedence; category key breaks ties deterministically.
      var clipped = dayActivities
      clipped.sort { lhs, rhs in
        if lhs.start != rhs.start {
          return lhs.start < rhs.start
        }
        if lhs.originalStart != rhs.originalStart { return lhs.originalStart < rhs.originalStart }
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        return lhs.id < rhs.id
      }
      var covered: [(start: Int, end: Int)] = []
      var assigned: [(start: Int, end: Int, key: String)] = []
      for item in clipped {
        if item.matches, summary.firstMatchingIDByCategory[item.key] == nil {
          summary.firstMatchingIDByCategory[item.key] = item.id
        }
        var cursor = item.start
        var newlyAssigned = 0.0
        for interval in covered where interval.end > cursor {
          if interval.start > cursor {
            let seconds = Double(min(interval.start, item.end) - cursor)
            assigned.append((cursor, min(interval.start, item.end), item.key))
            summary.secondsByCategory[item.key, default: 0] += seconds
            newlyAssigned += seconds
            cursor = min(interval.start, item.end)
          }
          cursor = max(cursor, interval.end)
          if cursor >= item.end { break }
        }
        if cursor < item.end {
          let seconds = Double(item.end - cursor)
          assigned.append((cursor, item.end, item.key))
          summary.secondsByCategory[item.key, default: 0] += seconds
          newlyAssigned += seconds
        }
        summary.totalSeconds += newlyAssigned
        covered.append((item.start, item.end))
        covered.sort { $0.start < $1.start }
        var merged: [(start: Int, end: Int)] = []
        for interval in covered {
          if let last = merged.indices.last, interval.start <= merged[last].end {
            merged[last].end = max(merged[last].end, interval.end)
          } else {
            merged.append(interval)
          }
        }
        covered = merged
      }
      // Intersect the unchanged category coverage with matching intervals. A
      // later matching card may overlap an earlier nonmatch in the same category;
      // it must still light up that coverage, without double-counting it.
      for slice in assigned {
        var cursor = slice.start
        for match in clipped where match.matches && match.key == slice.key {
          let start = max(cursor, match.start)
          let end = min(slice.end, match.end)
          if end > start {
            summary.matchingSecondsByCategory[slice.key, default: 0] += Double(end - start)
            cursor = end
          }
        }
      }
      result[day] = summary
    }
    return result
  }
}

struct MonthTimelineView: View {
  let selectedDate: Date
  let refreshTrigger: Int
  @Binding var hasAnyActivities: Bool
  var mutedCategoryKeys: Set<String> = []
  // Search annotates the existing bars without changing their geometry or totals.
  var searchQuery: String = ""
  let onSelectDay: (Date) -> Void
  var onSelectMatch: (Date, TimelineActivity) -> Void = { _, _ in }

  @EnvironmentObject private var categoryStore: CategoryStore
  @Environment(\.dayflowTheme) private var theme
  @State private var summaries: [String: MonthDaySummary] = [:]
  @State private var activitiesByID: [String: TimelineActivity] = [:]
  @State private var loadGeneration = 0
  @State private var loadTask: Task<Void, Never>?

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    calendar.firstWeekday = 2
    return calendar
  }()

  private var monthRange: TimelineMonthRange {
    TimelineMonthRange.containing(selectedDate)
  }

  /// First day of the month as a plain calendar date (midnight).
  private var firstDay: Date {
    let cal = Self.calendar
    return cal.date(from: cal.dateComponents([.year, .month], from: monthRange.monthStart))
      ?? monthRange.monthStart
  }

  private var dayCount: Int {
    Self.calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
  }

  /// Leading empty cells so the first day lands on the right weekday (Monday first).
  private var leadingBlanks: Int {
    let weekday = Self.calendar.component(.weekday, from: firstDay)
    return (weekday - Self.calendar.firstWeekday + 7) % 7
  }

  private var weekdayLabels: [String] {
    let symbols = Self.calendar.shortWeekdaySymbols
    let first = Self.calendar.firstWeekday - 1
    return (0..<7).map { symbols[(first + $0) % 7] }
  }

  private var idleKeys: Set<String> {
    Set(categoryStore.categories.filter(\.isIdle).map { categoryFilterKey($0.name) })
  }

  var body: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        ForEach(weekdayLabels, id: \.self) { label in
          Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
      }
      LazyVGrid(columns: columns, spacing: 6) {
        // Keep blank leading slots and day cells in one uniquely identified
        // sequence. Separate ForEach blocks can confuse LazyVGrid's child
        // identity when the number of leading blanks changes between months,
        // causing the first dates to disappear after navigating months.
        ForEach(0..<(leadingBlanks + max(dayCount, 1)), id: \.self) { slot in
          if slot < leadingBlanks {
            Color.clear.frame(height: 76)
          } else {
            dayCell(slot - leadingBlanks + 1)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear { load() }
    .onChange(of: monthRange) { load() }
    .onChange(of: refreshTrigger) { load() }
    .onChange(of: mutedCategoryKeys) { load() }
    .onChange(of: searchQuery) { load() }
    // New cards arrive while the view is open, so refresh like the day and week views do.
    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
      if AppVisibility.isMainWindowOnScreen { load() }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in load()
    }
    .onDisappear { loadTask?.cancel() }
  }

  private func date(forDay number: Int) -> Date {
    let cal = Self.calendar
    let day = cal.date(byAdding: .day, value: number - 1, to: firstDay) ?? firstDay
    return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
  }

  private func dayCell(_ number: Int) -> some View {
    let date = date(forDay: number)
    let key = DateFormatter.yyyyMMdd.string(from: date)
    let summary = summaries[key]
    let isSelected = key == DateFormatter.yyyyMMdd.string(from: selectedDate)
    let isFuture = MonthTimelineSummary.isFutureDay(date)

    return VStack(alignment: .leading, spacing: 4) {
        Text("\(number)")
          .font(.system(size: 13, weight: isSelected ? .bold : .medium))
          .foregroundColor(theme.textPrimary)
        Spacer(minLength: 0)
        if let summary, summary.totalSeconds > 0 {
          Text(Self.durationText(summary.totalSeconds))
            .font(.system(size: 11))
            .foregroundColor(theme.textSecondary)
          categoryBar(summary, date: date)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(theme.textPrimary.opacity(0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(theme.textPrimary.opacity(isSelected ? 0.4 : 0.1), lineWidth: 0.75)
      )
      .contentShape(Rectangle())
      .opacity(isFuture ? 0.4 : 1)
    .allowsHitTesting(!isFuture)
    .onTapGesture { if !isFuture { onSelectDay(date) } }
    .accessibilityElement(children: .contain)
    .accessibilityAction { if !isFuture { onSelectDay(date) } }
  }

  private func categoryBar(_ summary: MonthDaySummary, date: Date) -> some View {
    MonthCategorySearchBar(
      summary: summary, searchQuery: searchQuery, colorForKey: color(forCategoryKey:),
      onSelectMatch: { id in
        if let activity = activitiesByID[id] { onSelectMatch(date, activity) }
      },
      onSelectDay: { onSelectDay(date) }
    )
  }

  private func color(forCategoryKey key: String) -> Color {
    let matched = categoryStore.categories.first { categoryFilterKey($0.name) == key }
    let category =
      matched ?? categoryStore.categories.first ?? CategoryPersistence.defaultCategories.first!
    return Color(nsColor: NSColor(hex: category.colorHex) ?? .systemBlue)
  }

  static func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(rest)m" }
    return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
  }

  private func load() {
    loadTask?.cancel()
    loadGeneration += 1
    let generation = loadGeneration
    let range = monthRange
    let muted = mutedCategoryKeys
    let idle = idleKeys
    let searchTerms = TimelineSearch.terms(searchQuery)
    loadTask = Task.detached(priority: .userInitiated) {
      let activities = TimelineActivityLoader.activities(in: range)
      let result = MonthTimelineSummary.summarize(
        activities, mutedCategoryKeys: muted, idleCategoryKeys: idle, searchTerms: searchTerms)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard generation == loadGeneration else { return }
        activitiesByID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        summaries = result
        hasAnyActivities = !activities.isEmpty
      }
    }
  }
}

/// Uses the same totals and segment widths before and during search. Only opacity
/// changes. Keeping the renderer separate also allows native pixel verification.
struct MonthCategorySearchBar: View {
  let summary: MonthDaySummary
  let searchQuery: String
  let colorForKey: (String) -> Color
  let onSelectMatch: (String) -> Void
  let onSelectDay: () -> Void

  var body: some View {
    let parts = summary.secondsByCategory.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }
    return GeometryReader { geo in
      HStack(spacing: 0) {
        ForEach(parts, id: \.key) { part in
          let matching = min(part.value, summary.matchingSecondsByCategory[part.key] ?? 0)
          let searching = !TimelineSearch.terms(searchQuery).isEmpty
          HStack(spacing: 0) {
            if matching > 0 {
              Rectangle()
                .fill(colorForKey(part.key))
                .frame(width: geo.size.width * matching / max(summary.totalSeconds, 1))
            }
            Rectangle()
              .fill(colorForKey(part.key))
              .opacity(searching ? 0.2 : 1)
              .frame(width: geo.size.width * (part.value - matching) / max(summary.totalSeconds, 1))
          }
          .frame(height: 16)
          .contentShape(Rectangle())
          .highPriorityGesture(
            TapGesture(count: 2).exclusively(before: TapGesture())
              .onEnded { value in
                switch value {
                case .first:
                  if let id = summary.firstMatchingIDByCategory[part.key] {
                    onSelectMatch(id)
                  } else {
                    onSelectDay()
                  }
                case .second:
                  onSelectDay()
                }
              }
          )
          .accessibilityLabel(part.key)
          .accessibilityAction(named: Text("Open first search match")) {
            if let id = summary.firstMatchingIDByCategory[part.key] {
              onSelectMatch(id)
            }
          }
        }
      }
      .frame(height: 4)
      .clipShape(Capsule())
      .frame(height: 16)
    }
    .frame(height: 16)
  }

}
