import XCTest

@testable import Dayflow

final class WeeklyDashboardBuilderTests: XCTestCase {
  func testEqualClockTimesDoNotBecomeTwentyFourHoursOfActivity() {
    let weekRange = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_770_000_000))
    let day = DateFormatter.yyyyMMdd.string(from: weekRange.weekStart)
    let categories = [TimelineCategory(name: "Focus", colorHex: "4F8EF7", order: 0)]
    let cards = [
      card(day: day, appName: "Xcode", minutes: 0),
      card(day: day, appName: "Xcode", minutes: 60),
    ]
    let snapshot = WeeklyDashboardBuilder.build(
      cards: cards, previousWeekCards: [], categories: categories, weekRange: weekRange)

    XCTAssertEqual(snapshot.donut.totalMinutes, 60)
    XCTAssertEqual(snapshot.overview.totalFocusMinutes, 60)
    XCTAssertEqual(snapshot.sankey.categories.reduce(0) { $0 + $1.minutes }, 60)
    XCTAssertEqual(snapshot.sankey.apps.reduce(0) { $0 + $1.minutes }, 60)
    XCTAssertEqual(snapshot.sankey.links.reduce(0) { $0 + $1.minutes }, 60)
    XCTAssertEqual(snapshot.treemap.categories.flatMap(\.apps).reduce(0) { $0 + $1.duration }, 3600)
  }

  func testWeeklyClockRangesPreserveMidnightAndFourAMCrossings() {
    for (start, end, minutes) in [
      (540.0, 540.0, 0.0), (120.0, 120.0, 0.0),
      (1_430.0, 10.0, 20.0), (230.0, 250.0, 20.0), (540.0, 600.0, 60.0),
    ] {
      let range = WeeklyDashboardBuilder.normalizedMinuteRange(start: start, end: end)
      XCTAssertEqual(range.end - range.start, minutes)
    }
  }

  func testWeeklyDistributionExcludesIdleFromDonutTotal() {
    let weekRange = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_770_000_000))
    let day = DateFormatter.yyyyMMdd.string(from: weekRange.weekStart)
    let categories = [
      TimelineCategory(name: "Focus", colorHex: "4F8EF7", order: 0),
      TimelineCategory(name: "Idle", colorHex: "C7BDB5", order: 1, isIdle: true),
    ]
    let cards = [
      card(day: day, category: "Focus", appName: "Xcode", minutes: 60),
      card(day: day, category: "Idle", appName: "Idle", minutes: 120),
    ]

    let snapshot = WeeklyDashboardBuilder.build(
      cards: cards,
      previousWeekCards: [],
      categories: categories,
      weekRange: weekRange
    )

    XCTAssertEqual(snapshot.donut.totalMinutes, 60)
    XCTAssertEqual(snapshot.donut.items.map(\.name), ["Focus"])
  }

  func testWeeklyDashboardSnapshotIsSendableForBackgroundLoading() {
    let weekRange = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_770_000_000))
    let snapshot = WeeklyDashboardBuilder.build(
      cards: [],
      previousWeekCards: [],
      categories: [],
      weekRange: weekRange
    )

    assertSendable(snapshot)
  }

  func testSankeyCoalescesRealOtherAppWithOverflowBucket() {
    let weekRange = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_770_000_000))
    let day = DateFormatter.yyyyMMdd.string(from: weekRange.weekStart)
    let cards = [
      card(day: day, appName: "Other", minutes: 120),
      card(day: day, appName: "App 1", minutes: 110),
      card(day: day, appName: "App 2", minutes: 100),
      card(day: day, appName: "App 3", minutes: 90),
      card(day: day, appName: "App 4", minutes: 80),
      card(day: day, appName: "App 5", minutes: 70),
      card(day: day, appName: "App 6", minutes: 60),
      card(day: day, appName: "App 7", minutes: 50),
      card(day: day, appName: "App 8", minutes: 40),
      card(day: day, appName: "App 9", minutes: 30),
      card(day: day, appName: "App 10", minutes: 20),
    ]

    let snapshot = WeeklyDashboardBuilder.build(
      cards: cards,
      previousWeekCards: [],
      categories: [TimelineCategory(name: "Focus", colorHex: "4F8EF7", order: 0)],
      weekRange: weekRange
    )

    let otherApps = snapshot.sankey.apps.filter { $0.id == "other" }
    XCTAssertEqual(otherApps.count, 1)
    XCTAssertEqual(otherApps.first?.minutes, 170)
    XCTAssertEqual(Set(snapshot.sankey.apps.map(\.id)).count, snapshot.sankey.apps.count)
  }

  func testTreemapOtherAppKeepsItsBreakdownByCardTitle() {
    let weekRange = WeeklyDateRange.containing(Date(timeIntervalSince1970: 1_770_000_000))
    let day = DateFormatter.yyyyMMdd.string(from: weekRange.weekStart)
    let cards = [
      card(day: day, appName: "Other", minutes: 120),
      card(day: day, appName: "Xcode", minutes: 60),
    ]

    let snapshot = WeeklyDashboardBuilder.build(
      cards: cards,
      previousWeekCards: [],
      categories: [TimelineCategory(name: "Focus", colorHex: "4F8EF7", order: 0)],
      weekRange: weekRange
    )

    let apps = snapshot.treemap.categories.flatMap(\.apps)
    let other = apps.first { $0.name == "Other" }
    XCTAssertEqual(other?.isDrillable, true)
    XCTAssertEqual(other?.containedApps.map(\.name), ["Other work"])
    XCTAssertEqual(other?.containedApps.first?.duration, TimeInterval(120 * 60))
    XCTAssertEqual(apps.first { $0.name == "Xcode" }?.isDrillable, false)
  }

  private func card(
    day: String,
    category: String = "Focus",
    appName: String,
    minutes: Int
  ) -> TimelineCard {
    TimelineCard(
      recordId: nil,
      batchId: nil,
      startTimestamp: "09:00 AM",
      endTimestamp: endTime(minutesAfterNine: minutes),
      category: category,
      subcategory: "Work",
      title: "\(appName) work",
      summary: "Worked in \(appName)",
      detailedSummary: "",
      day: day,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: AppSites(primary: appName, secondary: nil)
    )
  }

  private func endTime(minutesAfterNine minutes: Int) -> String {
    let totalMinutes = 9 * 60 + minutes
    let hour = totalMinutes / 60
    let minute = totalMinutes % 60
    if hour == 12 {
      return String(format: "12:%02d PM", minute)
    }
    if hour > 12 {
      return String(format: "%d:%02d PM", hour - 12, minute)
    }
    return String(format: "%d:%02d AM", hour, minute)
  }

  private func assertSendable<T: Sendable>(_ value: T) {
    _ = value
  }
}
