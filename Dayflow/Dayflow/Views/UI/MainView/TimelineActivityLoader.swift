import Foundation

struct TimelineDisplaySegment {
  let activity: TimelineActivity
  private(set) var activities: [TimelineActivity]
  var start: Date
  var end: Date

  init(activity: TimelineActivity, start: Date, end: Date) {
    self.activity = activity
    self.activities = [activity]
    self.start = start
    self.end = end
  }

  init(activity: TimelineActivity, activities: [TimelineActivity], start: Date, end: Date) {
    self.activity = activity
    self.activities = activities
    self.start = start
    self.end = end
  }

  var failureCount: Int {
    guard activity.title == "Processing failed" else { return 0 }
    return activities.count
  }

  var batchIds: [Int64] {
    var seen = Set<Int64>()
    return activities.compactMap(\.batchId).filter { seen.insert($0).inserted }
  }

  mutating func appendFailure(_ activity: TimelineActivity) {
    activities.append(activity)
    start = min(start, activity.startTime)
    end = max(end, activity.endTime)
  }
}

struct TimelineRecordingProjectionWindow {
  let start: Date
  let end: Date
}

enum TimelineActivityLoader {
  // Stored card titles are always the English sentinel, regardless of UI language.
  static let failedTitle = "Processing failed"
  private static let failureGroupingGapTolerance: TimeInterval = 60

  static func dayPayload(
    for selectedDate: Date,
    storageManager: StorageManaging = StorageManager.shared,
    now: Date = Date()
  ) -> (dayString: String, timelineDate: Date, activities: [TimelineActivity]) {
    let timelineDate = timelineDisplayDate(from: selectedDate, now: now)
    let dayString = DateFormatter.yyyyMMdd.string(from: timelineDate)
    let cards = storageManager.fetchTimelineCards(forDay: dayString)
    let visibleCards = displayableCards(cards, storageManager: storageManager)
    let dayInfo = timelineDate.getDayInfoFor4AMBoundary()
    let pendingActivities = pendingCaptureActivities(
      from: dayInfo.startOfDay,
      to: dayInfo.endOfDay,
      storageManager: storageManager
    )
    return (dayString, timelineDate, buildActivities(from: visibleCards) + pendingActivities)
  }

  static func activities(
    in weekRange: TimelineWeekRange,
    storageManager: StorageManaging = StorageManager.shared
  ) -> [TimelineActivity] {
    // Fetch by stored day so each card lands in the column for the day it was recorded on.
    guard let firstDay = weekRange.days.first?.dayString,
      let lastDay = weekRange.days.last?.dayString
    else { return [] }
    let cards = storageManager.fetchTimelineCards(fromDay: firstDay, throughDay: lastDay)
    let pendingActivities: [TimelineActivity]
    if let firstDay = weekRange.days.first?.date.getDayInfoFor4AMBoundary(),
      let lastDay = weekRange.days.last?.date.getDayInfoFor4AMBoundary()
    {
      pendingActivities = pendingCaptureActivities(
        from: firstDay.startOfDay,
        to: lastDay.endOfDay,
        storageManager: storageManager
      )
    } else {
      pendingActivities = []
    }
    return buildActivities(from: displayableCards(cards, storageManager: storageManager))
      + pendingActivities
  }

  /// Month view: cards only. Pending capture is a week/day concern and scanning a
  /// month of captures on every load would cost more than it shows.
  static func activities(
    in monthRange: TimelineMonthRange,
    storageManager: StorageManaging = StorageManager.shared
  ) -> [TimelineActivity] {
    activities(from: monthRange.monthStart, to: monthRange.monthEnd, storageManager: storageManager)
  }

  static func activities(
    from start: Date,
    to end: Date,
    storageManager: StorageManaging = StorageManager.shared
  ) -> [TimelineActivity] {
    let cards = storageManager.fetchTimelineCardsByTimeRange(from: start, to: end)
    return buildActivities(from: displayableCards(cards, storageManager: storageManager))
  }

  private static func pendingCaptureActivities(
    from start: Date,
    to end: Date,
    storageManager: StorageManaging
  ) -> [TimelineActivity] {
    let gapSeconds = 5 * 60
    let intervals = storageManager.fetchPendingCaptureIntervals(
      from: Int(start.timeIntervalSince1970),
      to: Int(end.timeIntervalSince1970),
      groupingGapSeconds: gapSeconds
    )
    guard !intervals.isEmpty else { return [] }

    var merged: [(start: Int, end: Int)] = []
    for interval in intervals {
      if let last = merged.indices.last,
        interval.start <= merged[last].end + gapSeconds
      {
        merged[last].end = max(merged[last].end, interval.end)
      } else {
        merged.append(interval)
      }
    }

    let title = TimelineActivity.pendingAnalysisTitle
    let explanation = TimelineActivity.pendingAnalysisExplanation
    return merged.map { interval in
      let start = Date(timeIntervalSince1970: TimeInterval(interval.start))
      let end = Date(timeIntervalSince1970: TimeInterval(interval.end))
      return TimelineActivity(
        id: "pending-analysis:\(interval.start):\(interval.end)",
        recordId: nil,
        batchId: nil,
        startTime: start,
        endTime: end,
        title: title,
        summary: explanation,
        detailedSummary: explanation,
        category: "Pending analysis",
        subcategory: "pending",
        distractions: nil,
        videoSummaryURL: nil,
        screenshot: nil,
        appSites: nil,
        isBackupGenerated: nil,
        screenshots: nil,
        isPendingAnalysis: true
      )
    }
  }

  static func shouldDisplay(_ card: TimelineCard, storageManager: StorageManaging) -> Bool {
    guard card.title == "Processing failed" else { return true }
    return isRetryableFailedCard(card, storageManager: storageManager)
  }

  static func isRetryableFailedCard(_ card: TimelineCard, storageManager: StorageManaging) -> Bool {
    guard card.title == "Processing failed", let batchId = card.batchId else { return false }
    return hasRetrySourceScreenshots(for: batchId, storageManager: storageManager)
  }

  static func displayableCards(
    _ cards: [TimelineCard],
    storageManager: StorageManaging
  ) -> [TimelineCard] {
    let retryableBatchIds = retryableFailedBatchIds(in: cards, storageManager: storageManager)
    return cards.filter { card in
      guard card.title == failedTitle else { return true }
      guard let batchId = card.batchId else { return false }
      return retryableBatchIds.contains(batchId)
    }
  }

  /// Batch ids of the failed cards whose batch still has at least one screenshot
  /// file on disk (i.e. retryable), resolved with one batched read instead of a
  /// screenshotsForBatch query (plus file checks) per failed card.
  static func retryableFailedBatchIds(
    in cards: [TimelineCard],
    storageManager: StorageManaging
  ) -> Set<Int64> {
    let failedBatchIds = cards.compactMap { $0.title == failedTitle ? $0.batchId : nil }
    guard !failedBatchIds.isEmpty else { return [] }

    return Set(
      storageManager.screenshotsForBatches(failedBatchIds).compactMap { batchId, screenshots in
        screenshots.contains(where: \.isAvailable) ? batchId : nil
      })
  }

  private static func hasRetrySourceScreenshots(
    for batchId: Int64,
    storageManager: StorageManaging
  ) -> Bool {
    storageManager.screenshotsForBatch(batchId).contains(where: \.isAvailable)
  }

  static func buildActivities(from cards: [TimelineCard]) -> [TimelineActivity] {
    let calendar = Calendar.current
    let dayOffsets = displayOffsetsByDay(cards)
    var results: [TimelineActivity] = []
    var idCounts: [String: Int] = [:]
    results.reserveCapacity(cards.count)

    for card in cards {
      guard
        let baseDay = DateFormatter.yyyyMMdd.date(from: card.day),
        let clocks = clockTimes(for: card, dayOffset: dayOffsets[card.day])
      else {
        continue
      }

      let baseDate = calendar.startOfDay(for: baseDay)
      // Times before 4 AM belong to the next calendar date. The date is picked before setting
      // the time, so a 2:30 AM card isn't placed in the hour skipped on spring-forward day.
      let nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
      let startBase = clocks.start.hour < 4 ? nextDate : baseDate
      let endBase = clocks.end.hour < 4 ? nextDate : baseDate

      guard
        let adjustedStartDate = calendar.date(
          bySettingHour: clocks.start.hour,
          minute: clocks.start.minute,
          second: 0,
          of: startBase
        ),
        var adjustedEndDate = calendar.date(
          bySettingHour: clocks.end.hour,
          minute: clocks.end.minute,
          second: 0,
          of: endBase
        )
      else {
        continue
      }

      if adjustedEndDate < adjustedStartDate {
        adjustedEndDate =
          calendar.date(byAdding: .day, value: 1, to: adjustedEndDate) ?? adjustedEndDate
      }

      let baseId = TimelineActivity.stableId(
        recordId: card.recordId,
        batchId: card.batchId,
        startTime: adjustedStartDate,
        endTime: adjustedEndDate,
        title: card.title,
        category: card.category,
        subcategory: card.subcategory
      )

      let seenCount = idCounts[baseId, default: 0]
      idCounts[baseId] = seenCount + 1
      let finalId = seenCount == 0 ? baseId : "\(baseId)-\(seenCount)"

      results.append(
        TimelineActivity(
          id: finalId,
          recordId: card.recordId,
          batchId: card.batchId,
          startTime: adjustedStartDate,
          endTime: adjustedEndDate,
          title: card.title,
          summary: card.summary,
          detailedSummary: card.detailedSummary,
          category: card.category,
          subcategory: card.subcategory,
          distractions: card.distractions,
          videoSummaryURL: card.videoSummaryURL,
          screenshot: nil,
          appSites: card.appSites,
          isBackupGenerated: card.isBackupGenerated
        )
      )
    }

    return results
  }

  /// Week view only: joins consecutive segments into blocks of about `targetDuration`, so a day
  /// reads as a few blocks instead of a stack of minute-long slivers. A block takes the category
  /// with the most time in it. A gap longer than `maxGap` always starts a new block. The day
  /// view keeps the unmerged segments.
  static func resolveMacroblocks(
    from segments: [TimelineDisplaySegment],
    maxGap: TimeInterval = 60,
    targetDuration: TimeInterval = 600
  ) -> [TimelineDisplaySegment] {
    var groups: [[TimelineDisplaySegment]] = []
    var current: [TimelineDisplaySegment] = []
    for segment in segments {
      if let last = current.last, segment.start.timeIntervalSince(last.end) > maxGap {
        groups.append(current)
        current = []
      }
      current.append(segment)
      if let first = current.first, segment.end.timeIntervalSince(first.start) >= targetDuration {
        groups.append(current)
        current = []
      }
    }
    if !current.isEmpty { groups.append(current) }

    return groups.map { group in
      var totals: [String: TimeInterval] = [:]
      for segment in group {
        totals[segment.activity.category, default: 0] += segment.end.timeIntervalSince(segment.start)
      }
      let dominant =
        totals.max { lhs, rhs in lhs.value < rhs.value }?.key ?? group[0].activity.category
      let members = group.filter { $0.activity.category == dominant }.flatMap(\.activities)
      let representative =
        members.max { lhs, rhs in
          lhs.endTime.timeIntervalSince(lhs.startTime) < rhs.endTime.timeIntervalSince(rhs.startTime)
        } ?? group[0].activity
      return TimelineDisplaySegment(
        activity: representative,
        activities: group.flatMap(\.activities),
        start: group.map(\.start).min() ?? group[0].start,
        end: group.map(\.end).max() ?? group[0].end
      )
    }
  }

  /// The clock times a card is drawn at. Cards are drawn in the zone they were recorded in. On a
  /// day recorded in more than one zone, cards more than an hour away from the day's main zone
  /// are drawn in that main zone instead, so travel days don't overlap, as long as that keeps
  /// them on the same day. A one-hour difference is a daylight saving change, which keeps its
  /// own clock times.
  static func clockTimes(for card: TimelineCard, dayOffset: Int?) -> (
    start: (hour: Int, minute: Int), end: (hour: Int, minute: Int)
  )? {
    if let startTs = card.startTs, let endTs = card.endTs, let ownOffset = card.utcOffset,
      let dayOffset, abs(ownOffset - dayOffset) > 3600,
      ClockTime.logicalDay(of: startTs, offset: dayOffset) == card.day
    {
      return (clockTime(at: startTs, offset: dayOffset), clockTime(at: endTs, offset: dayOffset))
    }

    // Otherwise the stored labels, which are the clock times in the zone the card was recorded
    // in, including across a daylight saving change inside the card.
    guard let start = ClockTime.hourAndMinute(of: card.startTimestamp),
      let end = ClockTime.hourAndMinute(of: card.endTimestamp)
    else { return nil }
    return (start, end)
  }

  /// For each day, the UTC offset that covers the most of that day's cards.
  static func displayOffsetsByDay(_ cards: [TimelineCard]) -> [String: Int] {
    var secondsByDayAndOffset: [String: [Int: Int]] = [:]
    for card in cards {
      guard let startTs = card.startTs, let endTs = card.endTs, let offset = card.utcOffset
      else { continue }
      secondsByDayAndOffset[card.day, default: [:]][offset, default: 0] += max(60, endTs - startTs)
    }
    return secondsByDayAndOffset.compactMapValues { seconds in
      seconds.max { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
      }?.key
    }
  }

  /// The hour and minute a clock shows at `timestamp` in a zone `offset` seconds east of UTC.
  private static func clockTime(at timestamp: Int, offset: Int) -> (hour: Int, minute: Int) {
    let secondsOfDay = ((timestamp + offset) % 86_400 + 86_400) % 86_400
    return (secondsOfDay / 3600, secondsOfDay % 3600 / 60)
  }

  static func createDisplaySegments(from activities: [TimelineActivity])
    -> [TimelineDisplaySegment]
  {
    let sortedActivities = activities.sorted { lhs, rhs in
      if lhs.startTime == rhs.startTime {
        return lhs.endTime < rhs.endTime
      }
      return lhs.startTime < rhs.startTime
    }

    var segments: [TimelineDisplaySegment] = []
    segments.reserveCapacity(sortedActivities.count)

    for activity in sortedActivities {
      if activity.title == failedTitle,
        let lastIndex = segments.indices.last,
        segments[lastIndex].activity.title == failedTitle,
        // Waiting and failed stretches look and read differently, so they stay apart.
        segments[lastIndex].activity.waitingTitle == activity.waitingTitle,
        activity.startTime.timeIntervalSince(segments[lastIndex].end)
          <= failureGroupingGapTolerance
      {
        segments[lastIndex].appendFailure(activity)
      } else {
        segments.append(
          TimelineDisplaySegment(
            activity: activity,
            start: activity.startTime,
            end: activity.endTime
          ))
      }
    }

    return segments
  }

  static func recordingProjectionWindow(
    for timelineDate: Date,
    displaySegments: [TimelineDisplaySegment],
    now: Date = Date()
  ) -> TimelineRecordingProjectionWindow? {
    guard timelineIsToday(timelineDate, now: now) else { return nil }

    let dayInfo = timelineDate.getDayInfoFor4AMBoundary()
    let dayStart = dayInfo.startOfDay
    let dayEnd = dayInfo.endOfDay
    let cycleDuration: TimeInterval = 15 * 60
    let hardCap: TimeInterval = 40 * 60

    let centeredStart = now.addingTimeInterval(-(cycleDuration / 2))
    var windowStart = max(dayStart, centeredStart)
    var windowEnd = windowStart.addingTimeInterval(cycleDuration)

    if windowEnd > dayEnd {
      windowEnd = dayEnd
      windowStart = max(dayStart, windowEnd.addingTimeInterval(-cycleDuration))
    }

    windowEnd = min(windowEnd, windowStart.addingTimeInterval(hardCap))

    if windowEnd <= windowStart {
      return nil
    }

    let sortedSegments = displaySegments.sorted { $0.start < $1.start }
    var moved = true
    var iterations = 0
    let maxIterations = max(1, sortedSegments.count + 2)

    while moved {
      moved = false
      let previousStart = windowStart
      let previousEnd = windowEnd

      for segment in sortedSegments {
        let intersects = segment.end > windowStart && segment.start < windowEnd
        if intersects {
          windowStart = segment.end
          windowEnd = windowStart.addingTimeInterval(cycleDuration)

          if windowEnd > dayEnd {
            windowEnd = dayEnd
            windowStart = max(dayStart, windowEnd.addingTimeInterval(-cycleDuration))
          }

          windowEnd = min(windowEnd, windowStart.addingTimeInterval(hardCap))
          moved = true
          break
        }
      }

      if windowStart >= dayEnd {
        return nil
      }

      if moved {
        iterations += 1
        if windowStart == previousStart && windowEnd == previousEnd {
          return nil
        }
        if iterations >= maxIterations {
          return nil
        }
      }
    }

    guard windowEnd > windowStart else { return nil }
    return TimelineRecordingProjectionWindow(start: windowStart, end: windowEnd)
  }
}
