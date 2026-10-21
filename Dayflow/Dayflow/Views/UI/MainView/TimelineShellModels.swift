import Foundation

enum TimelineMode: String, CaseIterable, Identifiable {
  case hour
  case day
  case week
  case month

  var id: String { rawValue }

  /// Cmd+plus zooms in (month to week to day to hour); Cmd+minus zooms out. Clamped at both ends.
  func zoomed(by delta: Int) -> TimelineMode {
    let all = TimelineMode.allCases
    guard let index = all.firstIndex(of: self) else { return self }
    if delta > 0 { return all[max(index - 1, 0)] }
    if delta < 0 { return all[min(index + 1, all.count - 1)] }
    return self
  }

  var title: String {
    switch self {
    case .hour:
      return String(localized: "Hour")
    case .day:
      return String(localized: "Day")
    case .week:
      return String(localized: "Week")
    case .month:
      return String(localized: "Month")
    }
  }
}

struct TimelineWeekDay: Identifiable, Equatable, Sendable {
  let date: Date
  let dayString: String
  let weekdayLabel: String
  let dayNumber: String

  var id: String { dayString }
}

struct TimelineWeekRange: Equatable, Sendable {
  let weekStart: Date
  let weekEnd: Date
  let days: [TimelineWeekDay]

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    calendar.firstWeekday = 2
    return calendar
  }()

  private static let titleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMMd")
    return formatter
  }()

  private static let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E"
    return formatter
  }()

  private static let dayNumberFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d"
    return formatter
  }()

  private init(weekStart: Date, weekEnd: Date) {
    self.weekStart = weekStart
    self.weekEnd = weekEnd
    self.days = Self.buildDays(weekStart: weekStart)
  }

  private static func buildDays(weekStart: Date) -> [TimelineWeekDay] {
    let calendar = Self.calendar
    return (0..<7).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
        return nil
      }
      let normalizedDate = normalizedTimelineDate(date)
      return TimelineWeekDay(
        date: normalizedDate,
        dayString: DateFormatter.yyyyMMdd.string(from: normalizedDate),
        weekdayLabel: Self.weekdayFormatter.string(from: normalizedDate),
        dayNumber: Self.dayNumberFormatter.string(from: normalizedDate)
      )
    }
  }

  static func containing(_ date: Date, calendar: Calendar = Self.calendar) -> TimelineWeekRange {
    let timelineDate = timelineDisplayDate(from: date, now: date)
    let anchorDay = calendar.startOfDay(for: timelineDate)
    let weekday = calendar.component(.weekday, from: anchorDay)
    let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
    let weekStartDay =
      calendar.date(byAdding: .day, value: -daysFromWeekStart, to: anchorDay)
      ?? anchorDay
    let weekStart =
      calendar.date(bySettingHour: 4, minute: 0, second: 0, of: weekStartDay) ?? weekStartDay
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    return TimelineWeekRange(weekStart: weekStart, weekEnd: weekEnd)
  }

  func shifted(byWeeks weeks: Int, calendar: Calendar = Self.calendar) -> TimelineWeekRange {
    let shiftedStart = calendar.date(byAdding: .day, value: weeks * 7, to: weekStart) ?? weekStart
    let shiftedEnd = calendar.date(byAdding: .day, value: 7, to: shiftedStart) ?? shiftedStart
    return TimelineWeekRange(weekStart: shiftedStart, weekEnd: shiftedEnd)
  }

  var title: String {
    let displayedWeekEnd = Self.calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
    return
      String(
        localized:
          "\(Self.titleFormatter.string(from: weekStart)) - \(Self.titleFormatter.string(from: displayedWeekEnd))"
      )
  }

  var canNavigateForward: Bool {
    weekStart < Self.containing(Date()).weekStart
  }

  var containsToday: Bool {
    contains(Date())
  }

  func contains(_ date: Date) -> Bool {
    let timelineDate = timelineDisplayDate(from: date, now: date)
    let dayStart = timelineDate.getDayInfoFor4AMBoundary().startOfDay
    return dayStart >= weekStart && dayStart < weekEnd
  }
}

/// The calendar month containing a date, bounded at 4 AM like the week range.
struct TimelineMonthRange: Equatable, Sendable {
  let monthStart: Date
  let monthEnd: Date

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    calendar.firstWeekday = 2
    return calendar
  }()

  private static let titleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
    return formatter
  }()

  static func containing(_ date: Date, calendar: Calendar = Self.calendar) -> TimelineMonthRange {
    let timelineDate = timelineDisplayDate(from: date, now: date)
    let components = calendar.dateComponents([.year, .month], from: timelineDate)
    let firstDay = calendar.date(from: components) ?? calendar.startOfDay(for: timelineDate)
    let start = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: firstDay) ?? firstDay
    let nextFirst = calendar.date(byAdding: .month, value: 1, to: firstDay) ?? firstDay
    let end = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: nextFirst) ?? nextFirst
    return TimelineMonthRange(monthStart: start, monthEnd: end)
  }

  var title: String { Self.titleFormatter.string(from: monthStart) }

  var containsToday: Bool {
    let now = Date()
    return now >= monthStart && now < monthEnd
  }

  var canNavigateForward: Bool {
    monthStart < Self.containing(Date()).monthStart
  }
}
