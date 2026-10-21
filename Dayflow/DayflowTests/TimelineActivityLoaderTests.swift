import XCTest

@testable import Dayflow

final class TimelineActivityLoaderTests: XCTestCase {
  func testResolveDisplaySegmentsGroupsConsecutiveFailures() {
    let activities = [
      activity(
        id: "failure-3", startMinute: 31, endMinute: 46, title: "Processing failed", batchId: 3),
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 15, endMinute: 30, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].activity.id, "failure-1")
    XCTAssertEqual(segments[0].failureCount, 3)
    XCTAssertEqual(segments[0].batchIds, [1, 2, 3])
    XCTAssertEqual(segments[0].start, date(minute: 0))
    XCTAssertEqual(segments[0].end, date(minute: 46))
  }

  func testResolveDisplaySegmentsDoesNotGroupAcrossAnotherActivity() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(id: "idle", startMinute: 15, endMinute: 30, title: "Idle"),
      activity(
        id: "failure-2", startMinute: 30, endMinute: 45, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 3)
    XCTAssertEqual(segments.map(\.failureCount), [1, 0, 1])
  }

  func testResolveDisplaySegmentsDoesNotGroupFailuresSeparatedByMoreThanOneMinute() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 17, endMinute: 32, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments.map(\.failureCount), [1, 1])
  }

  func testWeekMacroblocksMergeConsecutiveSameCategory() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 5, title: "Short task", category: "Engineering"),
      activity(id: "b", startMinute: 5, endMinute: 14, title: "Main task", category: "Engineering"),
      activity(id: "c", startMinute: 14, endMinute: 20, title: "Idle", category: "Idle"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 14))
    XCTAssertEqual(blocks[0].activity.title, "Main task")
    XCTAssertEqual(blocks[1].activity.category, "Idle")
  }

  func testWeekMacroblocksJoinAlternatingCategoriesIntoTenMinuteBlocks() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 4, title: "Coding", category: "Engineering"),
      activity(id: "b", startMinute: 4, endMinute: 5, title: "Chat", category: "Communication"),
      activity(id: "c", startMinute: 5, endMinute: 9, title: "Coding more", category: "Engineering"),
      activity(id: "d", startMinute: 9, endMinute: 10, title: "Personal", category: "Personal"),
      activity(id: "e", startMinute: 10, endMinute: 12, title: "Coding last", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].start, date(minute: 0))
    XCTAssertEqual(blocks[0].end, date(minute: 10))
    XCTAssertEqual(blocks[0].activity.category, "Engineering")
    XCTAssertEqual(blocks[1].activity.category, "Engineering")
  }

  func testWeekMacroblocksKeepSeparateAcrossAGap() {
    let segments = TimelineActivityLoader.resolveDisplaySegments(from: [
      activity(id: "a", startMinute: 0, endMinute: 5, title: "Task", category: "Engineering"),
      activity(id: "b", startMinute: 7, endMinute: 10, title: "Task", category: "Engineering"),
    ])

    let blocks = TimelineActivityLoader.resolveMacroblocks(from: segments)

    XCTAssertEqual(blocks.count, 2)
  }

  private func activity(
    id: String,
    startMinute: Int,
    endMinute: Int,
    title: String,
    batchId: Int64? = nil,
    category: String? = nil
  ) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: nil,
      batchId: batchId,
      startTime: date(minute: startMinute),
      endTime: date(minute: endMinute),
      title: title,
      summary: "",
      detailedSummary: "",
      category: category ?? (title == "Idle" ? "Idle" : "System"),
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: false
    )
  }

  private func date(minute: Int) -> Date {
    Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60))
  }
}

final class SidebarShortcutTests: XCTestCase {
  func testCommandNumbersSelectTheMainSectionsInSidebarOrder() {
    XCTAssertEqual(SidebarIcon.forCommandNumber(1), .timeline)
    XCTAssertEqual(SidebarIcon.forCommandNumber(2), .daily)
    XCTAssertEqual(SidebarIcon.forCommandNumber(3), .weekly)
    XCTAssertEqual(SidebarIcon.forCommandNumber(4), .chat)
    XCTAssertEqual(SidebarIcon.forCommandNumber(5), .flow)
    XCTAssertEqual(SidebarIcon.forCommandNumber(6), .agents)
  }

  func testCommandNumbersOutsideTheMainSectionsSelectNothing() {
    XCTAssertNil(SidebarIcon.forCommandNumber(0))
    XCTAssertNil(SidebarIcon.forCommandNumber(7))
    XCTAssertNil(SidebarIcon.forCommandNumber(9))
  }
}

final class SidebarFlowVisibilityTests: XCTestCase {
  func testHidingFlowRemovesOnlyFlowFromTheSidebar() {
    let visible = SidebarIcon.visibleIcons(hideFlow: true)
    XCTAssertFalse(visible.contains(.flow))
    XCTAssertEqual(visible.count, SidebarIcon.allCases.count - 1)
    XCTAssertTrue(visible.contains(.timeline))
    XCTAssertTrue(visible.contains(.settings))
  }

  func testShowingFlowKeepsTheFullSidebar() {
    XCTAssertEqual(SidebarIcon.visibleIcons(hideFlow: false), SidebarIcon.allCases)
  }
}

final class TimelineZoomAndHintTests: XCTestCase {
  func testZoomInMovesFromMonthDownToHourAndStopsAtHour() {
    XCTAssertEqual(TimelineMode.month.zoomed(by: 1), .week)
    XCTAssertEqual(TimelineMode.week.zoomed(by: 1), .day)
    XCTAssertEqual(TimelineMode.day.zoomed(by: 1), .hour)
    XCTAssertEqual(TimelineMode.hour.zoomed(by: 1), .hour)
  }

  func testZoomOutMovesFromHourUpToMonthAndStopsAtMonth() {
    XCTAssertEqual(TimelineMode.hour.zoomed(by: -1), .day)
    XCTAssertEqual(TimelineMode.day.zoomed(by: -1), .week)
    XCTAssertEqual(TimelineMode.week.zoomed(by: -1), .month)
    XCTAssertEqual(TimelineMode.month.zoomed(by: -1), .month)
  }

  func testZoomByZeroKeepsMode() {
    for mode in TimelineMode.allCases {
      XCTAssertEqual(mode.zoomed(by: 0), mode)
    }
  }

  func testModeOrderIsHourDayWeekMonth() {
    XCTAssertEqual(TimelineMode.allCases, [.hour, .day, .week, .month])
    XCTAssertEqual(TimelineMode.hour.title, "Hour")
    XCTAssertEqual(TimelineMode.month.title, "Month")
  }

  func testMonthRangeRunsFromFirstDayToNextFirstAtFourAM() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 14, hour: 12))!
    let range = TimelineMonthRange.containing(date, calendar: calendar)
    XCTAssertEqual(
      calendar.dateComponents([.year, .month, .day, .hour], from: range.monthStart),
      DateComponents(year: 2026, month: 2, day: 1, hour: 4))
    XCTAssertEqual(
      calendar.dateComponents([.year, .month, .day, .hour], from: range.monthEnd),
      DateComponents(year: 2026, month: 3, day: 1, hour: 4))
  }

  func testSidebarShortcutLabelsAreVisibleText() {
    XCTAssertEqual(SidebarIcon.timeline.shortcutLabel, "⌘1")
    XCTAssertEqual(SidebarIcon.agents.shortcutLabel, "⌘6")
    XCTAssertEqual(SidebarIcon.settings.shortcutLabel, "⌘,")
  }

  func testSidebarHintsShowCommandNumbers() {
    XCTAssertEqual(SidebarIcon.timeline.shortcutHint, "Timeline (⌘1)")
    XCTAssertEqual(SidebarIcon.agents.shortcutHint, "Agents (⌘6)")
    XCTAssertEqual(SidebarIcon.settings.shortcutHint, "Settings (⌘,)")
  }
}

final class WeeklyTreemapOtherDrillDownTests: XCTestCase {
  private func app(_ name: String, minutes: Int) -> WeeklyTreemapApp {
    WeeklyTreemapApp(
      id: name, name: name, duration: TimeInterval(minutes * 60), change: nil)
  }

  func testOtherTileKeepsTheAppsItContains() {
    let other = WeeklyTreemapApp.aggregate(containing: [app("Slack", minutes: 30), app("Mail", minutes: 10)])
    XCTAssertEqual(other.containedApps.map(\.name), ["Slack", "Mail"])
  }

  func testMergingAddsAppsWithoutLosingTheOnesAlreadyInside() {
    let other = WeeklyTreemapApp.aggregate(containing: [app("Slack", minutes: 30)])
    let merged = other.merging(app("Mail", minutes: 10))
    XCTAssertEqual(merged.containedApps.map(\.name), ["Slack", "Mail"])
    XCTAssertEqual(merged.duration, TimeInterval(40 * 60))
  }

  func testOnlyTilesWithContentsAreDrillable() {
    XCTAssertFalse(app("Slack", minutes: 30).isDrillable)
    XCTAssertTrue(WeeklyTreemapApp.aggregate(containing: [app("Slack", minutes: 30)]).isDrillable)
  }

  func testNestedOtherTilesAreFlattened() {
    let inner = WeeklyTreemapApp.aggregate(containing: [app("Slack", minutes: 30)])
    let outer = WeeklyTreemapApp.aggregate(containing: [inner, app("Mail", minutes: 10)])
    XCTAssertEqual(outer.containedApps.map(\.name), ["Slack", "Mail"])
  }
}

final class BrowserPrivacyDecisionTests: XCTestCase {
  func testHostParsingLowercasesAndDropsScheme() {
    XCTAssertEqual(BrowserPrivacy.host(from: "https://WWW.Example.com/path?q=1"), "www.example.com")
    XCTAssertNil(BrowserPrivacy.host(from: "not a url"))
  }

  func testExcludedDomainMatchesItselfAndSubdomainsOnly() {
    let excluded = ["example.com"]
    XCTAssertTrue(BrowserPrivacy.isExcluded(host: "example.com", excludedDomains: excluded))
    XCTAssertTrue(BrowserPrivacy.isExcluded(host: "www.example.com", excludedDomains: excluded))
    XCTAssertFalse(BrowserPrivacy.isExcluded(host: "notexample.com", excludedDomains: excluded))
    XCTAssertFalse(BrowserPrivacy.isExcluded(host: "example.com.evil.net", excludedDomains: excluded))
  }

  func testIncognitoIsRedactedOnlyWhenTheSettingIsOn() {
    XCTAssertEqual(
      BrowserPrivacy.redactionReason(isIncognito: true, url: nil, hidesIncognito: true, excludedDomains: []),
      .privateWindow)
    XCTAssertNil(
      BrowserPrivacy.redactionReason(isIncognito: true, url: nil, hidesIncognito: false, excludedDomains: []))
  }

  func testExcludedSiteIsRedacted() {
    XCTAssertEqual(
      BrowserPrivacy.redactionReason(
        isIncognito: false, url: "https://video.example.com/x", hidesIncognito: true,
        excludedDomains: ["example.com"]),
      .excludedSite)
    XCTAssertNil(
      BrowserPrivacy.redactionReason(
        isIncognito: false, url: "https://news.org/x", hidesIncognito: true,
        excludedDomains: ["example.com"]))
  }
}

final class TimelineModeSwitchLayoutTests: XCTestCase {
  func testSwitchIsWideEnoughForEveryMode() {
    // A fixed 104pt container clipped the row to Day and Week once Hour and Month existed.
    XCTAssertEqual(
      TimelineMode.switchWidth, TimelineMode.segmentWidth * CGFloat(TimelineMode.allCases.count))
    XCTAssertEqual(TimelineMode.allCases.count, 4)
  }
}

final class TimelineHourAndMonthBehaviorTests: XCTestCase {
  func testDayScrollTargetIsTwoHoursBeforeNow() {
    // 15:00 is 11 hours after the 4 AM start; two hours before that is index 9.
    XCTAssertEqual(
      CanvasTimelineDataView.nowTargetHourIndex(
        currentHour: 15, hourHeight: TimelineScale.hourHeight), 9)
  }

  func testHourScrollTargetIsTheCurrentHourAtTripleScale() {
    // At 3x one hour is taller than the 25% gap, so going two hours back would hide "now".
    XCTAssertEqual(
      CanvasTimelineDataView.nowTargetHourIndex(
        currentHour: 15, hourHeight: TimelineScale.hourHeight * 3), 11)
  }

  func testScrollTargetHandlesHoursAfterMidnight() {
    // 02:00 is 22 hours after the 4 AM start; two hours before that is index 20.
    XCTAssertEqual(
      CanvasTimelineDataView.nowTargetHourIndex(
        currentHour: 2, hourHeight: TimelineScale.hourHeight), 20)
  }

  func testMonthCellsAfterTodayAreFuture() {
    let calendar = Calendar.current
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
    let todayNoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
    let tomorrowNoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
    XCTAssertFalse(MonthTimelineSummary.isFutureDay(todayNoon, now: now, calendar: calendar))
    XCTAssertTrue(MonthTimelineSummary.isFutureDay(tomorrowNoon, now: now, calendar: calendar))
  }
}

final class SettingsTabOrderTests: XCTestCase {
  func testAccountIsSecondToLastAndStorageIsTheDefault() {
    XCTAssertEqual(
      SettingsView.SettingsTab.allCases.map(\.rawValue),
      ["storage", "privacy", "providers", "aiTools", "data", "account", "other"])
    XCTAssertEqual(SettingsView.SettingsTab.defaultTab, .storage)
  }
}

final class HourViewReadabilityTests: XCTestCase {
  func testShortCardsOnlyShowTextWhenAskedTo() {
    XCTAssertFalse(CanvasActivityCard.showsText(durationMinutes: 5, showsShortCardText: false))
    XCTAssertTrue(CanvasActivityCard.showsText(durationMinutes: 5, showsShortCardText: true))
    XCTAssertTrue(CanvasActivityCard.showsText(durationMinutes: 12, showsShortCardText: false))
  }

  func testHourZoomGivesAOneMinuteCardRoomForItsTitle() {
    let pointsPerMinute = TimelineScale.hourHeight * TimelineMode.hourZoom / 60
    XCTAssertGreaterThanOrEqual(pointsPerMinute, 16)
  }

  func testHourCardFontIsSmallerThanTheDayFont() {
    XCTAssertEqual(CanvasTimelineDataView.cardFontSize(base: 16, showsShortCardText: false), 16)
    XCTAssertEqual(CanvasTimelineDataView.cardFontSize(base: 16, showsShortCardText: true), 13)
  }
}
